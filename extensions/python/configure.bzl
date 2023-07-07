## extensions.bzl
load("//:repositories.bzl", "pybind11_dependency")
load("//:python_configure.bzl", "python_configure")

def _pybind_extension_impl(ctx):
    pybind11_dependency()

    for mod in ctx.modules:
        for configure in mod.tags.configure:
            python_configure(
                name = configure.name,
                python_version = configure.python_version,
                python_interpreter_target = configure.python_interpreter_target,
            )

def _python_configure():
    attrs = dict({
        "name": attr.string(default = "local_config_python"),
        "python_version": attr.string(default = ""),
        "python_interpreter_target": attr.label(default = None),
    })
    return attrs

pybind11 = module_extension(
    tag_classes = {
        "configure": tag_class(attrs = _python_configure()),
    },
    implementation = _pybind_extension_impl,
)
