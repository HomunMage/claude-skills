FROM mcr.microsoft.com/playwright/python:v1.50.0-noble

WORKDIR /app

# Install playwright Python package matching the base image version
RUN pip install --no-cache-dir playwright==1.50.0

# Copy scripts
COPY *.py ./

# Create output directory
RUN mkdir -p /output

CMD ["tail", "-f", "/dev/null"]
