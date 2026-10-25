import os
from flask import Flask, jsonify

app = Flask(__name__)

@app.get("/health")
def health():
    return jsonify(status="healthy"), 200

@app.get("/demo")
def demo():
    return jsonify(
        message=os.getenv("APP_MESSAGE", "Hello from AWS EKS!"),
        version=os.getenv("APP_VERSION", "v1")
    ), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)