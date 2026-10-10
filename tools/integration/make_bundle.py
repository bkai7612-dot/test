import sys, os, json, importlib.util
"""Builds build/integration_bundle.luau: real client + server controllers on a mocked Roblox runtime."""
sp = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(sp))
spec = importlib.util.spec_from_file_location("btb", os.path.join(repo, "tools/build_test_bundle.py"))
btb = importlib.util.module_from_spec(spec); spec.loader.exec_module(btb)
project = json.load(open(os.path.join(repo, "default.project.json")))
entries = []
btb.walk_tree(project["tree"], [], entries)
WANT = ("ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer")
out = [open(os.path.join(sp, "mock.luau")).read(), open(os.path.join(sp, "prelude.luau")).read()]
for vpath, kind, _ in entries:
    if vpath[0] in WANT:
        out.append("__path({%s}, %s)" % (", ".join(btb.luau_string(p) for p in vpath), btb.luau_string("ModuleScript" if kind == "module" else "Folder")))
for vpath, kind, f in entries:
    if kind != "module" or vpath[0] not in WANT: continue
    src = btb.transform_source(open(f).read())
    out.append("do\n\tlocal __node = __path({%s}, \"ModuleScript\")\n\trawset(__node, \"_fn\", function(script)\n\t\tlocal require = __require\n%s\n\tend)\nend" % (", ".join(btb.luau_string(p) for p in vpath), src))
out.append(open(os.path.join(sp, "scenarios.luau")).read())
os.makedirs(os.path.join(repo, "build"), exist_ok=True)
open(os.path.join(repo, "build", "integration_bundle.luau"), "w").write("\n".join(out))
print("ok")
