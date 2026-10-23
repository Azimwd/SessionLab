from django.apps import AppConfig


class LabConfig(AppConfig):
    name = "lab"

    def ready(self):
        from .api import schema
