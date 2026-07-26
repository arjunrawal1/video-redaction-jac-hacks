"""Media-layer helpers backing the redaction pipeline.

Importing this package loads `.env` from the project root. Jac does not read
`.env` on its own, and the credentials for Vertex and Textract are only ever
consumed through this package, so loading here means neither the CLI nor the
server needs a shell with exports set up.
"""

from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Real environment variables win, so a deploy can override the file.
load_dotenv(PROJECT_ROOT / ".env", override=False)
