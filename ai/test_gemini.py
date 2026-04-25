import requests
import os

api_key = os.getenv("GEMINI_API_KEY")

url = f"https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent?key={api_key}"

headers = {
    "Content-Type": "application/json"
}

data = {
    "contents": [
        {
            "parts": [
                {"text": "Explain in 3 lines how AI can detect stolen sports images."}
            ]
        }
    ]
}

response = requests.post(url, headers=headers, json=data)

response_json = response.json()

text = response_json["candidates"][0]["content"]["parts"][0]["text"]

print(text)