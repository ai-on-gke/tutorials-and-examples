// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Package main encrypts the local file data and stores it in a GCS bucket.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	storage "cloud.google.com/go/storage"
	"github.com/tink-crypto/tink-go-gcpkms/v2/integration/gcpkms"
	"github.com/tink-crypto/tink-go/v2/aead"
)

var (
	kekURI        = flag.String("kek_uri", "", "The Cloud KMS URI of the key encryption key.")
	localFilePath = flag.String("local_path", "", "Path to the local file to encrypt.")
	gcsBlobPath   = flag.String("gcs_blob_path", "", "Path to the GCS blob.")
)

func main() {
	flag.Parse()

	if *kekURI == "" {
		log.Fatalf("kek_uri flag can not be empty.")
	}
	if *localFilePath == "" {
		log.Fatalf("local_path flag can not be empty.")
	}
	if *gcsBlobPath == "" {
		log.Fatalf("gcs_blob_path flag can not be empty.")
	}

	ctx := context.Background()
	if err := encrypt(ctx, *kekURI, *gcsBlobPath); err != nil {
		log.Fatalf("encrypt failed: %v", err)
	}
}

func encrypt(ctx context.Context, uri, blobPath string) error {
	bucket, object, err := getBucketAndObject(blobPath)
	if err != nil {
		return err
	}
	// Create KMS and GCS clients.
	kmsClient, err := gcpkms.NewClientWithOptions(ctx, uri)
	if err != nil {
		return fmt.Errorf("failed to create handle: %w", err)
	}

	gcsClient, err := storage.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("failed to create storage client: %w", err)
	}
	defer gcsClient.Close()

	kekAEAD, err := kmsClient.GetAEAD(uri)
	if err != nil {
		return fmt.Errorf("failed to create AEAD: %w", err)
	}

	primitive := aead.NewKMSEnvelopeAEAD2(aead.AES256GCMKeyTemplate(), kekAEAD)

	// Get plain text to encrypt from GCS bucket.
	plainText, err := os.ReadFile(*localFilePath)
	if err != nil {
		return err
	}

	// Encrypt the data.
	associatedData := []byte(*gcsBlobPath)
	encryptedText, err := primitive.Encrypt(plainText, associatedData)
	if err != nil {
		return err
	}
	// Upload encrypted bytes to GCS.
	gcsWriter := gcsClient.Bucket(bucket).Object(object).NewWriter(ctx)
	defer func() {
		if err := gcsWriter.Close(); err != nil {
			log.Printf("failed to write file at %s: %v", blobPath, err)
		}
	}()
	if _, err := gcsWriter.Write(encryptedText); err != nil {
		return err
	}
	return nil
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
