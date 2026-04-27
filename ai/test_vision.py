from google.cloud import vision
import requests

client = vision.ImageAnnotatorClient()

#  Use a VERY common image
image_url = "https://www.gstatic.com/webp/gallery/1.jpg"

# Download bytes (more reliable than URL mode)
resp = requests.get(image_url)
content = resp.content

image = vision.Image(content=content)

response = client.web_detection(image=image)
web = response.web_detection

print("=== DEBUG INFO ===")
print("Full matching pages:", len(web.pages_with_matching_images))
print("Partial matching images:", len(web.partial_matching_images))
print("Visually similar images:", len(web.visually_similar_images))

print("\n=== FULL MATCHES ===")
for page in web.pages_with_matching_images[:5]:
    print(page.url, page.score)

print("\n=== PARTIAL MATCHES ===")
for img in web.partial_matching_images[:5]:
    print(img.url)

print("\n=== VISUALLY SIMILAR ===")
for img in web.visually_similar_images[:5]:
    print(img.url)

print("\n=== LABELS ===")
for label in web.best_guess_labels:
    print(label.label)