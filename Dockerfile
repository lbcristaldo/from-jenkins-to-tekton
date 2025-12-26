FROM python:3.11-slim

# Set timezone (I decided to mantain the original, but can be changed)
ENV TZ=Asia/Shanghai
RUN apt-get update && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# Create working directory
RUN mkdir -p /hello
WORKDIR /hello

# Copy requirements first for better caching
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy all application files
COPY . .

EXPOSE 5000

# Health check 
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import http.client, sys; conn = http.client.HTTPConnection('localhost', 5000); conn.request('GET', '/health'); resp = conn.getresponse(); sys.exit(0 if resp.status == 200 else 1)"

# Create non-root user and switch to it
RUN addgroup --system app && adduser --system --group app
RUN chown -R app:app /hello
USER app

# Run the application
CMD ["python3", "run.py"]

