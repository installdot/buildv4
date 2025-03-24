import time
import os
import glob
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager

# Function to find ChromeDriver automatically
def find_chromedriver():
    common_paths = [
        r"C:\Program Files (x86)\Application\Chrome\chromedriver.exe",
        r"C:\Program Files\Google\Chrome\Application\chromedriver.exe",
        r"C:\Users\*\AppData\Local\Google\Chrome\Application\chromedriver.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chromedriver.exe",
    ]
    
    for path in common_paths:
        found = glob.glob(path.replace("*", os.getlogin()))  # Replace * with the current username
        if found:
            return found[0]  # Return first found path

    return None  # No path found

# Try finding ChromeDriver automatically
CHROMEDRIVER_PATH = find_chromedriver()

# If not found, use WebDriver Manager as a fallback
if not CHROMEDRIVER_PATH:
    print("ChromeDriver not found, using WebDriver Manager...")
    service = Service(ChromeDriverManager().install())
else:
    print(f"Using ChromeDriver at: {CHROMEDRIVER_PATH}")
    service = Service(CHROMEDRIVER_PATH)

# Initialize Chrome options
options = Options()
options.add_argument("--window-size=800,600")  # Small window size
options.add_argument("--disable-blink-features=AutomationControlled")  # Bypass bot detection

# Launch WebDriver
driver = webdriver.Chrome(service=service, options=options)

# Collect multiple links from user input
links = []
while True:
    user_input = input("Enter a link (Press Enter to finish): ").strip()
    if not user_input:
        break
    links.append(user_input)

print("\nStarting process...\n")

# Process each link
for link in links:
    print(f"Opening: {link}")
    driver.get(link)  # Open the link

    # Wait for the completion page to appear
    while True:
        current_url = driver.current_url
        if "https://androidmodvip.io.vn/newbot/hoanthanh.php?" in current_url:
            print(f"Detected completion page: {current_url}")
            time.sleep(5)  # Wait a few seconds before proceeding
            break  # Move to the next link

print("\nAll links processed. Closing browser...")
driver.quit()
