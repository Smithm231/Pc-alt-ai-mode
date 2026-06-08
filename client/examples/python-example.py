"""
python-example.py — Chat with the inference PC using the OpenAI SDK.

Install:  pip install openai
Usage:    python client/examples/python-example.py
"""

import os
from openai import OpenAI

HOST  = os.getenv("INFERENCE_HOST", "inference-pc.local")
PORT  = int(os.getenv("INFERENCE_PORT", "8080"))   # nginx proxy
MODEL = os.getenv("INFERENCE_MODEL", "llama3.2")

client = OpenAI(
    base_url=f"http://{HOST}:{PORT}/v1",
    api_key="not-needed",  # llama-server doesn't require a key
)

def chat(prompt: str, model: str = MODEL) -> str:
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        stream=False,
    )
    return response.choices[0].message.content


def stream_chat(prompt: str, model: str = MODEL) -> None:
    print(f"[{model}] ", end="", flush=True)
    with client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        stream=True,
    ) as stream:
        for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                print(delta, end="", flush=True)
    print()


if __name__ == "__main__":
    print(f"Inference endpoint: http://{HOST}:{PORT}/v1")
    print(f"Model: {MODEL}\n")
    stream_chat("Explain GPU inference in two sentences.")
