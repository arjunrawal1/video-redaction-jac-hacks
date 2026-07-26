"""Locate the byLLM source shipped inside the jac binary.

Diagnostic only: prints where jaclang and its byllm subpackage live so the
implementation can be read directly.
"""

import sys;
import jaclang;
import jaclang.byllm;
import jaclang.byllm.lib;

with entry {
    print("jaclang:", jaclang.__file__);
    print("jaclang path:", list(jaclang.__path__));
    print("byllm:", jaclang.byllm.__file__);
    print("byllm path:", list(jaclang.byllm.__path__));
    print("lib:", jaclang.byllm.lib.__file__);
    print("prefix:", sys.prefix);
    print("executable:", sys.executable);
    mods = sorted([m for m in sys.modules if "byllm" in m]);
    for m in mods {
        print("  mod", m, getattr(sys.modules[m], "__file__", None));
    }
}
