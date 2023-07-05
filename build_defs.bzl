# Copyright (c) 2019 The Pybind Development Team. All rights reserved.
#
# All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Build rules for pybind11."""

def register_extension_info(**kwargs):
    pass

PYBIND_COPTS = select({
    "@pybind11//:msvc_compiler": [],
    "//conditions:default": [
        "-fexceptions",
    ],
})

PYBIND_FEATURES = [
    "-use_header_modules",  # Required for pybind11.
    "-parse_headers",
]

PYBIND_DEPS = [
    "@pybind11",
    "@local_config_python//:python_headers",
]

# Builds a Python extension module using pybind11.
# This can be directly used in python with the import statement.
# This adds rules for a .so binary file.
def _pybind_extension_impl(
        name,
        copts = [],
        features = [],
        linkopts = [],
        tags = [],
        deps = [],
        **kwargs):
    # Mark common dependencies as required for build_cleaner.
    tags = tags + ["req_dep=%s" % dep for dep in PYBIND_DEPS]

    native.cc_binary(
        name = name,
        copts = copts + PYBIND_COPTS + select({
            "@pybind11//:msvc_compiler": [],
            "//conditions:default": [
                "-fvisibility=hidden",
            ],
        }),
        features = features + PYBIND_FEATURES,
        linkopts = linkopts + select({
            "@pybind11//:msvc_compiler": [],
            "@pybind11//:osx": [],
            "//conditions:default": ["-Wl,-Bsymbolic"],
        }),
        linkshared = 1,
        tags = tags,
        deps = deps + PYBIND_DEPS,
        **kwargs
    )

def pybind_extension(
        name,
        copts = [],
        features = [],
        linkopts = [],
        tags = [],
        deps = [],
        **kwargs):
    _pybind_extension_impl(
        name = name + ".so",
        copts = copts,
        features = features,
        linkopts = linkopts,
        tags = tags,
        deps = deps,
        **kwargs
    )

    # rename the <name>.so file to <name>.pyd on windows
    native.genrule(
        name = "gen_" + name + ".pyd",
        srcs = [":" + name + ".so"],
        outs = [name + ".pyd"],
        cmd = "cp $< $@",
    )

    # alias the <name> target to the correct file extension
    native.alias(
        name = name,
        actual = select({
            "@platforms//os:windows": ":" + "gen_" + name + ".pyd",
            "//conditions:default": ":" + name + ".so",
        }),
    )

# Builds a pybind11 compatible library. This can be linked to a pybind_extension.
def pybind_library(
        name,
        copts = [],
        features = [],
        tags = [],
        deps = [],
        **kwargs):
    # Mark common dependencies as required for build_cleaner.
    tags = tags + ["req_dep=%s" % dep for dep in PYBIND_DEPS]

    native.cc_library(
        name = name,
        copts = copts + PYBIND_COPTS,
        features = features + PYBIND_FEATURES,
        tags = tags,
        deps = deps + PYBIND_DEPS,
        **kwargs
    )

# Builds a C++ test for a pybind_library.
def pybind_library_test(
        name,
        copts = [],
        features = [],
        tags = [],
        deps = [],
        **kwargs):
    # Mark common dependencies as required for build_cleaner.
    tags = tags + ["req_dep=%s" % dep for dep in PYBIND_DEPS]

    native.cc_test(
        name = name,
        copts = copts + PYBIND_COPTS,
        features = features + PYBIND_FEATURES,
        tags = tags,
        deps = deps + PYBIND_DEPS + [
            "//util/python:python_impl",
            "//util/python:test_main",
        ],
        **kwargs
    )

def _pybind_stubgen_impl(ctx):
    output_dir_name = ctx.attr.module_name + ctx.attr.root_module_suffix
    output_dir = ctx.actions.declare_directory(output_dir_name)
    runfiles = ctx.runfiles(files = ctx.files._stubgen_runfiles)
    runfiles = runfiles.merge(ctx.runfiles(files = ctx.files.src + [ctx.executable.tool]))
    inputs = ctx.files.src + [ctx.executable.tool]

    if ctx.executable.code_formatter:
        runfiles = runfiles.merge(ctx.runfiles(files = [ctx.executable.code_formatter]))
        inputs.append(ctx.executable.code_formatter)

    # Tool exists check.
    if ctx.executable.tool.path:
        print("Tool exists at path: {}".format(ctx.executable.tool.path))
    else:
        fail("Tool not found at path: {}".format(ctx.executable.tool.path))

    args = [
        ctx.executable.tool.path,
        ctx.attr.module_name,
        "-o",
        output_dir.path,
    ]

    # Print the command to be executed for debugging.
    #    print("Command to be executed: " + " ".join(args))

    #    print("root_module_suffix: " + ctx.attr.root_module_suffix)
    #    if ctx.attr.root_module_suffix:
    #        args.extend(["--root-module-suffix", "\"{}\""
    #            .format(ctx.attr.root_module_suffix)])

    if ctx.attr.no_setup_py:
        args.append("--no-setup-py")

    if ctx.attr.ignore_invalid:
        args.extend(["--ignore-invalid", " ".join(ctx.attr.ignore_invalid)])

    if ctx.attr.skip_signature_downgrade:
        args.append("--skip-signature-downgrade")

    if ctx.attr.bare_numpy_ndarray:
        args.append("--bare-numpy-ndarray")

    if ctx.attr.log_level:
        args.extend(["--log-level", ctx.attr.log_level])

    args.extend([
        "&&",
        "cp -R",
        "{}/{}-stubs/*".format(output_dir.path, ctx.attr.module_name),
        output_dir.path,
        "&&",
        "rm -rf",
        "{}/{}-stubs".format(output_dir.path, ctx.attr.module_name),
    ])

    if ctx.attr.code_formatter:
        args.extend([
            "&&",
            ctx.executable.code_formatter.path,
            output_dir.path,
        ])

    pythonpath = ctx.files.src[0].dirname

    # Generate stubs.
    ctx.actions.run_shell(
        outputs = [output_dir],
        inputs = inputs,
        command = " ".join(args),
        env = {"PYTHONPATH": pythonpath},
    )

    # After running the stub generator, create the manifest file.
    #    ctx.actions.write(
    #        output = manifest_file,
    #        content = "\n".join([f.path for f in output_dir.files]),
    #    )

    # Returning the directory as the output.
    return DefaultInfo(
        files = depset([output_dir]),
        runfiles = runfiles,
    )

pybind_stubgen = rule(
    implementation = _pybind_stubgen_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        "module_name": attr.string(mandatory = True),
        "tool": attr.label(executable = True, cfg = "host", allow_files = True),
        "root_module_suffix": attr.string(default = "-stubs"),
        "no_setup_py": attr.bool(),
        "ignore_invalid": attr.string_list(),
        "skip_signature_downgrade": attr.bool(),
        "bare_numpy_ndarray": attr.bool(),
        "log_level": attr.string(),
        "code_formatter": attr.label(executable = True, cfg = "host", allow_files = True),
        "_stubgen_runfiles": attr.label(),
    },
)

# Register extension with build_cleaner.
register_extension_info(
    extension = pybind_extension,
    label_regex_for_dep = "{extension_name}",
)

register_extension_info(
    extension = pybind_library,
    label_regex_for_dep = "{extension_name}",
)

register_extension_info(
    extension = pybind_library_test,
    label_regex_for_dep = "{extension_name}",
)
