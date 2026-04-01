# =============================================================================
# backend/Dockerfile
# -----------------------------------------------------------------------------
# Builds the Docker image for BOTH the backend API and the worker.
# The same image is used for two different Kubernetes Deployments:
#   - backend:  runs gunicorn (default CMD below)
#   - worker:   overrides CMD with ["python", "worker.py"] in k8s/helpdesk.yaml
# =============================================================================

# Use the slim variant to minimize image size (no build tools, no extras)
FROM python:3.12-slim

# Set working directory inside the container
WORKDIR /app

# Copy requirements first — Docker layer caching optimization.
# If only source code changes (not dependencies), this layer is reused
# and pip install is skipped, making rebuilds much faster.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy all source code (app.py, worker.py, etc.)
COPY . .

# Force Python to flush stdout/stderr immediately.
# Without this, logs are buffered and may not appear in CloudWatch for minutes.
ENV PYTHONUNBUFFERED=1

# Document that the container listens on port 5000 (informational only)
EXPOSE 5000

# Default command: run the Flask app with gunicorn (production WSGI server).
# Gunicorn handles multiple concurrent requests; Flask's dev server cannot.
# The worker Deployment overrides this CMD with ["python", "worker.py"].
CMD ["gunicorn", "-b", "0.0.0.0:5000", "app:app"]
