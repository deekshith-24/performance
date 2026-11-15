from results_auth import configure_results_auth
from locust import HttpUser, task
from urllib3.exceptions import InsecureRequestWarning
import urllib3

urllib3.disable_warnings(InsecureRequestWarning)


class ListRecordsTest(HttpUser):
    """Read the default first page of Results records."""
    def on_start(self):
        self.client.verify = False
        configure_results_auth(self.client)

    @task
    def get_records(self) -> None:
        """List records using the API's default pagination."""
        self.client.get(
            "/apis/results.tekton.dev/v1alpha2/parents/-/results/-/records",
            name='/records',
            timeout=(10, 30),
        )
