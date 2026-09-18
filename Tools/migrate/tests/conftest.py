import shutil
import sys
from pathlib import Path

import pytest

# Make `import migrate` / `import frontmatter` work regardless of how pytest is invoked.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

FIXTURES = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def vault(tmp_path: Path) -> Path:
    """A private, mutable copy of the synthetic fixture vault under tmp_path.

    The checked-in fixture at tests/fixtures/vault/ is never touched by a test —
    every test gets its own copy so tests can run --apply freely and in parallel.
    """
    dst = tmp_path / "vault"
    shutil.copytree(FIXTURES / "vault", dst)
    return dst
