import Config

config :wallaby,
  otp_app: :dr_validator,
  driver: Wallaby.Chrome,
  # base_url: set to Phoenix endpoint URL when an HTTP server is added, e.g.:
  #   base_url: "http://localhost:4002"
  # Wallaby.Browser.visit/2 requires this for relative and non-http paths.
  # The smoke test uses execute_script instead of visit, so it is not needed yet.
  screenshot_dir: "test/screenshots",
  screenshot_on_failure: true,
  chrome: [
    headless: true,
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu"
    ]
  ]
