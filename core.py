import tempfile
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

DEFAULT_PRINT_OPTIONS = {
    "paperWidth": 8.27,
    "paperHeight": 11.69,
    "displayHeaderFooter": False,
}


def build_print_options(options: dict = None):
    merged = DEFAULT_PRINT_OPTIONS.copy()
    if options:
        merged.update(options)
    return merged


def generate_pdf(html: str, print_options: dict) -> str:
    """Return base64-encoded pdf"""

    with tempfile.NamedTemporaryFile(suffix=".html") as tmp:
        tmp.write(html.encode())
        tmp.seek(0)

        driver = build_driver()
        driver.get("file://{}".format(tmp.name))

        pdf = driver.execute_cdp_cmd("Page.printToPDF", print_options)["data"]
        driver.quit()

        return pdf


def build_driver():
    options = Options()
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-gpu")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--single-process")
    return webdriver.Chrome(options=options)
