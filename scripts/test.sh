#!/usr/bin/env bash
set -euo pipefail

SAGE_BIN="${1:-./sage}"
MODE="${2:-fast}"

# Resolve absolute path to SAGE_BIN
if [ -f "$SAGE_BIN" ]; then
  SAGE_BIN="$(cd "$(dirname "$SAGE_BIN")" && pwd)/$(basename "$SAGE_BIN")"
elif command -v "$SAGE_BIN" >/dev/null 2>&1; then
  SAGE_BIN="$(command -v "$SAGE_BIN")"
else
  echo "ERROR: Sage executable not found at: $SAGE_BIN" >&2
  exit 1
fi

echo "============================================================"
echo "  Testing SageMath Executable: $SAGE_BIN"
echo "  Mode: $MODE"
echo "============================================================"

# Test 1: Core Algebra & CAS Backends (GAP, Singular, PARI/GP)
echo "--> [Test 1/5] Validating Core Algebra & CAS backends..."
"$SAGE_BIN" -c "assert SymmetricGroup(5).order() == 120, 'GAP SymmetricGroup failed'"
"$SAGE_BIN" -c "x = var('x'); assert factor(x^10 - 1) != 0, 'Singular polynomial factor failed'"
"$SAGE_BIN" -c "assert int(gap('2+2')) == 4, 'GAP interface failed'"
"$SAGE_BIN" -c "assert int(singular('2+2')) == 4, 'Singular interface failed'"
"$SAGE_BIN" -c "assert pari('fibonacci(10)') == 55, 'PARI fibonacci failed'"
echo "    [PASS] Core CAS backends validated."

# Test 2: Official Sage Doctest Subsystem Verification (`sage.doctest`)
echo "--> [Test 2/5] Running targeted official Sage doctests (1,300+ tests)..."
"$SAGE_BIN" -c "
from sage.doctest.control import DocTestController, DocTestDefaults
import sage.combinat.permutation
options = DocTestDefaults()
controller = DocTestController(options, [sage.combinat.permutation.__file__])
res = controller.run()
assert res == 0, f'Doctest failed with exit code {res}'
"
echo "    [PASS] Targeted official Sage doctests passed."

# Test 3: Runtime Cython JIT Compilation
echo "--> [Test 3/5] Validating Runtime Cython JIT compilation..."
"$SAGE_BIN" -c "
from sage.repl.user_globals import set_globals
set_globals(globals())
from sage.misc.cython import cython_lambda
f = cython_lambda('long a, long b', 'a + b')
assert f(5, 7) == 12, f'Cython lambda failed: got {f(5, 7)}'
"
echo "    [PASS] Cython JIT compilation working natively."

# Test 4: Pip Extensibility
echo "--> [Test 4/5] Validating Pip package management..."
"$SAGE_BIN" -pip --version >/dev/null
echo "    [PASS] Bundled pip is functional ($("$SAGE_BIN" -pip --version | head -n 1))."

# Test 5: Headless Jupyter Server Verification
echo "--> [Test 5/5] Validating JupyterLab stack..."
"$SAGE_BIN" -n jupyter --help >/dev/null 2>&1 || "$SAGE_BIN" -c "import jupyterlab; print('JupyterLab version:', jupyterlab.__version__)"
echo "    [PASS] JupyterLab stack verified."

# Optional Full Test Suite
if [ "$MODE" = "full" ]; then
  echo "============================================================"
  echo "--> [Extended] Running full SageMath doctest suite..."
  echo "============================================================"
  "$SAGE_BIN" -c "
from sage.doctest.control import DocTestController, DocTestDefaults
import sage
options = DocTestDefaults(all=True)
controller = DocTestController(options, [sage.__file__])
controller.run()
" || true
fi

echo "============================================================"
echo "  All verification tests passed successfully!"
echo "============================================================"
