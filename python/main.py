# main.py
import logging
import sys
from hlc import HLC # Requires hlc.py

if __name__ == "__main__":
    # --- Setup Logging ---
    # Clear previous handlers
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)

    # Configure logging (level, format, output)
    log_format = '%(asctime)s - %(levelname)s - [%(module)s:%(lineno)d] - %(message)s'
    logging.basicConfig(
        level=logging.INFO, # Set desired level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        format=log_format,
        handlers=[
            logging.StreamHandler(sys.stdout) # Log to console
            # Optionally add FileHandler:
            # logging.FileHandler("hlc_app.log", mode='w') # Log to file (overwrite)
        ]
    )
    logging.info("--- Application Start ---")

    # --- Run Application ---
    try:
        app = HLC()
        app.run()
    except Exception as e:
        logging.exception("An unhandled exception occurred during application execution:")
        print(f"\nAn critical error occurred. Please check the logs.") # User-friendly message
    finally:
        logging.info("--- Application End ---")
        print("\nApplication finished.")

