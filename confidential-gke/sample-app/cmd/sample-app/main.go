// Package main retreives encrypted data on a GCS bucket and decrypts it using an attestation token and Cloud KMS.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	storage "cloud.google.com/go/storage"
	"github.com/golang-jwt/jwt/v5"
	"github.com/hashicorp/go-retryablehttp"
	"github.com/tink-crypto/tink-go-gcpkms/v2/integration/gcpkms"
	"github.com/tink-crypto/tink-go/v2/aead"
	option "google.golang.org/api/option"
)

var (
	kekURI        = flag.String("kek_uri", "", "The Cloud KMS URI of the key encryption key.")
	gcsBlobPath   = flag.String("gcs_blob_path", "", "Path to the GCS blob.")
	projectNumber = flag.String("project_number", "", "Project number where workload identity pool is located.")
	wipName       = flag.String("wip_name", "", "Workload Identity Pool name.")
	wipProvider   = flag.String("wip_provider", "", "Workload Identity Pool provider for attestation.")
)

const (
	socketPath           = "/run/launcher-agent/teeserver.sock"
	tokenEndpoint        = "http://localhost/v1/gke/token"
	attestationTokenPath = "/data/attestation_verifier_claims_token"
)

type confGKE struct {
	TEEPolicyDigest string `json:"tee_policy_digest"`
}

type subMods struct {
	ConfidentialGKE confGKE `json:"confidential_gke"`
}

type customClaim struct {
	HWModel   string   `json:"hwmodel"`
	SWName    string   `json:"swname"`
	SWVersion []string `json:"swversion"`
	SubMods   subMods  `json:"submods"`
	jwt.RegisteredClaims
}

type credentialSource struct {
	FilePath string `json:"file"`
}

type credentialConfig struct {
	UniverseDomain   string           `json:"universe_domain"`
	CredentialType   string           `json:"type"`
	Audience         string           `json:"audience"`
	SubjectTokenType string           `json:"subject_token_type"`
	TokenURL         string           `json:"token_url"`
	CredentialSource credentialSource `json:"credential_source"`
}

var (
	credConfigJSON        []byte
	refreshTokenOpSummary strings.Builder
	jwtErr                error
)

func main() {
	flag.Parse()

	// Register sample function to handle all requests.
	mux := http.NewServeMux()
	mux.HandleFunc("/", sample)

	// Use PORT environment variable, or default to 8080.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// start the web server on port and accept requests.
	if err := refreshJWTRoutine(); err != nil {
		fmt.Fprintf(&refreshTokenOpSummary, "refreshJWT loopJWTRefresh: %v\n", err)
		jwtErr = err
	}

	log.Printf("Server listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func decodeJWT(token []byte) (*jwt.Token, error) {
	accessToken := string(token)
	fmt.Fprintf(&refreshTokenOpSummary, "Token from the attestation service: %s\n", accessToken)
	parser := jwt.NewParser()
	claim := &customClaim{}
	// Use ParseUnverified because we just need to decode for the expire time.
	// Validation of the token is done on the server side by Workload Identity Federation.
	jwtToken, _, err := parser.ParseUnverified(accessToken, claim)
	if err != nil {
		fmt.Fprintf(&refreshTokenOpSummary, "jwt.Parse failed: %v\n", err)
		return nil, err
	}
	return jwtToken, nil
}

func refreshJWT() error {
	fmt.Fprintf(&refreshTokenOpSummary, "Starting JWT Refresh Operation at %v\n", time.Now())
	token, err := getJwt()
	if err != nil {
		return err
	}
	// Write the data to the file with read/write permissions for the owner.
	if err := os.WriteFile(attestationTokenPath, token, 0644); err != nil {
		return err
	}
	// Reset JWT error after successful operation.
	jwtErr = nil
	// Decode the JWT to get the experation time to know when to refresh it.
	jwtToken, err := decodeJWT(token)
	if err != nil {
		return err
	}
	expireTime, err := jwtToken.Claims.GetExpirationTime()
	if err != nil {
		return err
	}
	// Setup the refresh operation to happen again after the token's expire time.
	refreshDuration := time.Until(expireTime.Time)
	fmt.Fprintf(&refreshTokenOpSummary, "Refreshing JWT in %f minutes\n", refreshDuration.Minutes())
	time.AfterFunc(refreshDuration, func() {
		if err := refreshJWT(); err != nil {
			fmt.Fprintf(&refreshTokenOpSummary, "refreshJWT failed: %v\n", err)
		}
	})
	return nil
}

func refreshJWTRoutine() error {
	// One time setup.
	if err := validateFlags(); err != nil {
		return fmt.Errorf("error validating flags: %w", err)
	}

	audience := fmt.Sprintf("//iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s/providers/%s", *projectNumber, *wipName, *wipProvider)
	credConfig := credentialConfig{
		UniverseDomain:   "googleapis.com",
		CredentialType:   "external_account",
		Audience:         audience,
		SubjectTokenType: "urn:ietf:params:oauth:token-type:jwt",
		TokenURL:         "https://sts.googleapis.com/v1/token",
		CredentialSource: credentialSource{
			FilePath: attestationTokenPath,
		},
	}
	var err error
	credConfigJSON, err = json.Marshal(credConfig)
	if err != nil {
		return fmt.Errorf("error marshaling credential config: %w", err)
	}
	// Initial call.
	if err := refreshJWT(); err != nil {
		return fmt.Errorf("refreshJWT failed: %w", err)
	}

	return nil
}

func sample(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	// Reset the summary at the end of every request.
	defer refreshTokenOpSummary.Reset()

	log.Printf("Serving request: %s", r.URL.Path)

	if err := validateFlags(); err != nil {
		fmt.Fprintf(w, "error validating flags: %v\n", err)
		return
	}

	fmt.Fprintf(w, "Using Credential Config:\n%s\n", string(credConfigJSON))
	if len(credConfigJSON) == 0 {
		fmt.Fprintf(w, "credential config was not generated successfully, skipping operation.")
		return
	}

	if jwtErr != nil {
		fmt.Fprintf(w, "error obtaining JWT: %v\n", jwtErr)
		return
	}

	host, _ := os.Hostname()
	fmt.Fprintf(w, "Hostname: %s\n", host)
	// Output any errors or information from the token refresh operations to help with debugging.
	fmt.Fprintf(w, "JWT Refresh Operation Summary:\n%s\n", refreshTokenOpSummary.String())

	file, err := getFileFromGCS(ctx, credConfigJSON)
	if err != nil {
		fmt.Fprintf(w, "Error getting file from GCS: %s\n", err)
		return
	} else {
		fmt.Fprintf(w, "Succesfully downloaded encrypted file from GCS\n")
	}

	decrypted, err := gcpKmsKeyEnvelopeAeadDecrypt(ctx, credConfigJSON, []byte(file), *kekURI)
	if err != nil {
		fmt.Fprintf(w, "Error decrypting file: %s\n", err)
	} else {
		fmt.Fprintf(w, "Decrypted file:\n%s\n", string(decrypted))
	}

}

func getJwt() ([]byte, error) {
	client := retryablehttp.NewClient()
	// Configure retry options (optional)
	// Sets the maximum number of retries (default is 4)
	client.RetryMax = 5

	// Sets the initial backoff wait time (default is 1 second)
	// and the maximum wait time (default is 30 seconds).
	client.RetryWaitMin = 1 * time.Second
	client.RetryWaitMax = 5 * time.Second

	client.HTTPClient.Transport = &http.Transport{
		// Set the DialContext field to a function that creates
		// a new network connection to a Unix domain socket
		DialContext: func(_ context.Context, _, _ string) (net.Conn, error) {
			return net.Dial("unix", socketPath)
		},
	}

	resp, err := client.Get(tokenEndpoint)
	if err != nil {
		return nil, err
	}

	log.Printf("Response from launcher: %v\n", resp)
	text, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read resp.Body: %w", err)
	}
	log.Printf("Token from the attestation service: %s\n", text)

	return text, nil
}

func getFileFromGCS(ctx context.Context, credConfig []byte) (string, error) {

	client, err := storage.NewClient(ctx, option.WithCredentialsJSON(credConfig))
	if err != nil {
		return "", fmt.Errorf("failed to create storage client: %w", err)
	}
	defer client.Close()

	bucket, object, err := getBucketAndObject(*gcsBlobPath)
	if err != nil {
		return "", err
	}

	reader, err := client.Bucket(bucket).Object(object).NewReader(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to create reader: %w", err)
	}
	defer reader.Close()

	bytes, err := io.ReadAll(reader)
	if err != nil {
		return "", fmt.Errorf("failed to read all bytes: %w", err)
	}

	return string(bytes), nil
}

func gcpKmsKeyEnvelopeAeadDecrypt(ctx context.Context, credConfig, ciphertext []byte, kekURI string) ([]byte, error) {

	client, err := gcpkms.NewClientWithOptions(ctx, kekURI, option.WithCredentialsJSON(credConfig))
	if err != nil {
		return nil, fmt.Errorf("failed to create handle: %w", err)
	}

	kekAEAD, err := client.GetAEAD(kekURI)
	if err != nil {
		return nil, fmt.Errorf("failed to create AEAD: %w", err)
	}

	associatedData := []byte(*gcsBlobPath)
	primitive := aead.NewKMSEnvelopeAEAD2(aead.AES256GCMKeyTemplate(), kekAEAD)
	decrypted, err := primitive.Decrypt(ciphertext, associatedData)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt: %w", err)
	}
	return decrypted, nil
}

func getBucketAndObject(blobPath string) (string, string, error) {
	const gcsPrefix = "gs://"
	if !strings.HasPrefix(blobPath, gcsPrefix) {
		return "", "", fmt.Errorf("GCS Path must start with prefix %s: %s", gcsPrefix, blobPath)
	}
	path := blobPath[len(gcsPrefix):]
	parts := strings.Split(path, "/")
	if len(parts) < 2 {
		return "", "", fmt.Errorf("GCS blob paths must be in format gs://bucket-name/object-name, got %s", blobPath)
	}
	return parts[0], parts[1], nil
}

func validateFlags() error {
	if *kekURI == "" {
		return fmt.Errorf("kek_uri flag can not be empty")
	}
	if *gcsBlobPath == "" {
		return fmt.Errorf("gcs_blob_path flag can not be empty")
	}
	if *projectNumber == "" {
		return fmt.Errorf("project_number flag can not be empty")
	}
	if *wipName == "" {
		return fmt.Errorf("wip_name flag can not be empty")
	}
	if *wipProvider == "" {
		return fmt.Errorf("wip_provider flag can not be empty")
	}
	return nil
}
