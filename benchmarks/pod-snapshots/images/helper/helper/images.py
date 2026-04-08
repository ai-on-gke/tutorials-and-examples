from abc import ABC, abstractmethod
import os
import subprocess
import pathlib as pl
import shlex
import logging

logger = logging.getLogger("helper")

class ImageHelper(ABC):
    USERNAME: str

    def pull_images_with_ctr(self, images: list[str]):
        password = self._get_password()
        for image in images:
            logger.info(f"Pulling image {image}")
            subprocess.run(
                f'ctr -n k8s.io image pull --user="$CTR_CREDENTIALS" {shlex.quote(image)}',
                shell=True,
                check=True,
                env={
                    "CTR_CREDENTIALS": f"{self.__class__.USERNAME}:{password}"
                }
            )

    def copy_public_images_to_registry(
        self,
        images: list[dict[str, str]],
    ):
        password = self._get_password()
        for img in images:
            src = img["src"]
            dest = img["dest"]
            logger.info(f"Copying image {src} to {dest}")
            subprocess.run(
                f'skopeo copy --dest-creds "$CTR_CREDENTIALS" docker://{shlex.quote(src)} docker://{shlex.quote(dest)}',
                shell=True,
                check=True,
                env={
                    "CTR_CREDENTIALS": f"{self.__class__.USERNAME}:{password}"
                }
            )    

    def _get_password(self) -> str:
        try:
            password=subprocess.run(
                self._get_token_cli_command(),
                shell=True,
                check=True,
                capture_output=True
            ).stdout.decode().strip()
        except subprocess.CalledProcessError as e:
            logger.exception(f"Error. Stderr: {e.stderr}")
            raise

        return password


    @abstractmethod
    def _get_token_cli_command(self) -> str:
        pass

class GCPImageHelper(ImageHelper):
    USERNAME="oauth2accesstoken"
    
    def _get_token_cli_command(self) -> str:
        return "gcloud auth print-access-token"

class AWSImageHelper(ImageHelper):
    USERNAME="AWS"

    def _get_token_cli_command(self) -> str:
        return "aws ecr get-login-password"


class AzureImageHelper(ImageHelper):
    USERNAME = "00000000-0000-0000-0000-000000000000"

    def _get_token_cli_command(self):
        return f"az acr login --name {shlex.quote(self.registry_name)} --expose-token --output tsv --query accessToken"

    def __init__(self, registry_name):
        self.registry_name = registry_name


def pull_images_with_ctr(
    cloud_provider_type: str,
    images: list[str],
):
    image_helper = create_image_helper(cloud_provider_type)
    image_helper.pull_images_with_ctr(images)

def copy_public_images_to_registry(
    cloud_provider_type: str,
    images: list[dict[str, str]],
):
    image_helper = create_image_helper(cloud_provider_type)

    image_helper.copy_public_images_to_registry(images)


def create_image_helper(cloud_provider_type: str) -> ImageHelper:
    match cloud_provider_type:
        case 'gcp':
            return GCPImageHelper()
        case 'aws':
            return AWSImageHelper()
        case 'azure':
            azure_acr_registry_name=os.environ["AZURE_ACR_REGISTRY_NAME"]
            login_azure()
            return AzureImageHelper(azure_acr_registry_name)
        case _:
            raise ValueError(f"Unknown cloud provider type: {cloud_provider_type}")


def login_azure():
    subprocess.run(
        'az login --federated-token "$FEDERATED_TOKEN" --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID"',
        shell=True,
        check=True,
        env={
            "FEDERATED_TOKEN": pl.Path(os.environ["AZURE_FEDERATED_TOKEN_FILE"]).read_text(),
            "AZURE_CLIENT_ID": os.environ["AZURE_CLIENT_ID"],
            "AZURE_TENANT_ID": os.environ["AZURE_TENANT_ID"],
        }
    )

