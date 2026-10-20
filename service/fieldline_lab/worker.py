import os

from celery import Celery

from .service import JobService
from .settings import redis_url

celery_app = Celery("fieldline", broker=redis_url(), backend=None)
celery_app.conf.update(
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    worker_prefetch_multiplier=1,
    task_default_queue="fieldline",
    broker_connection_retry_on_startup=True,
)


def dispatch_celery(job_id: str) -> None:
    execute_job.delay(job_id)


def dispatch_job(job_id: str) -> None:
    if os.environ.get("REDIS_DISPATCH", "1") == "1":
        dispatch_celery(job_id)


@celery_app.task(name="fieldline.execute")
def execute_job(job_id: str) -> None:
    JobService(dispatch=dispatch_celery).execute(job_id)
