def copy_to_dir(ctx, srcs, relative_root):
    outs = []
    for i in srcs:
        o = ctx.actions.declare_file(i.path[len(relative_root)+1:])
        ctx.action(
            inputs = [i],
            outputs = [o],
            command = 'cp "$1" "$2"',
            arguments = [i.path, o.path]
        )
        outs.append(o)
    return outs

def _hugo_site_impl(ctx):
    hugo = ctx.executable.hugo
    hugo_inputs = [hugo]
    hugo_args = []

    # Copy the config file into place
    config_file = ctx.actions.declare_file(ctx.file.config.basename)
    ctx.action(
        inputs = [ctx.file.config],
        outputs = [config_file],
        command = 'cp "$1" "$2"',
        arguments = [ctx.file.config.path, config_file.path]
    )
    hugo_inputs.append(config_file)

    # Copy all the files over
    content_files = copy_to_dir(ctx, ctx.files.content, ctx.file.config.dirname)
    static_files = copy_to_dir(ctx, ctx.files.static, ctx.file.config.dirname)
    image_files = copy_to_dir(ctx, ctx.files.images, ctx.file.config.dirname)
    layout_files = copy_to_dir(ctx, ctx.files.layouts, ctx.file.config.dirname)
    data_files = copy_to_dir(ctx, ctx.files.data, ctx.file.config.dirname)
    hugo_inputs += content_files + static_files + image_files + layout_files + data_files

    # Copy the theme
    if ctx.attr.theme:
        theme = ctx.attr.theme.hugo_theme
        hugo_args += ["--theme", theme.name]
        for i in theme.files:
            if i.short_path.startswith("../"):
                o_filename = "/".join(["themes", theme.name] + i.short_path.split("/")[2:])
            else:
                # This was wrong before.... short_path is relative to the execution root, which is might be under 5 files! The themese should just go in the directory to which they glob....
                # so I've had to hack this with a hard-coded 2 since my theme folder is static-site/biztrox from the exec root!
                o_filename = "/".join(["themes", theme.name] + i.short_path.split("/")[2:])
            o = ctx.actions.declare_file(o_filename)
            ctx.action(
                inputs = [i],
                outputs = [o],
                command = 'cp "$1" "$2"',
                arguments = [i.path, o.path],
            )
            hugo_inputs.append(o)

    # Prepare hugo command
    hugo_outputdir = ctx.actions.declare_directory(ctx.label.name)
    hugo_args += [
        "--source", config_file.dirname,
        "--themesDir", "themes",
        "--destination", hugo_outputdir.basename
    ]

    if ctx.attr.quiet:
        hugo_args.append("--quiet")
    if ctx.attr.verbose:
        hugo_args.append("--verbose")
    if ctx.attr.base_url:
        hugo_args.append("--baseURL", ctx.attr.base_url)
    
    ctx.actions.run(
        mnemonic = "GoHugo",
        progress_message = "Generating hugo site",
        executable = hugo,
        arguments = hugo_args,
        inputs = hugo_inputs,
        outputs = [hugo_outputdir],
	execution_requirements = {"no-sandbox": "1"}
    )
    

    return [DefaultInfo(files = depset([hugo_outputdir]))]

hugo_site = rule(
    implementation = _hugo_site_impl,
    attrs = {
        # Hugo config file
        "config": attr.label(
            allow_files = [".toml", ".yaml", ".json"],
            single_file = True,
            mandatory = True,
        ),
        # Files to be included in the content/ subdir
        "content": attr.label_list(
            allow_files = True,
            mandatory = True,
        ),
        # Files to be included in the static/ subdir
        "static": attr.label_list(
            allow_files = True,
        ),
        # Files to be included in the images/ subdir
        "images": attr.label_list(
            allow_files = True,
        ),
        # Files to be included in the layouts/ subdir
        "layouts": attr.label_list(
            allow_files = True,
        ),
        # Files to be included in the data/ subdir
        "data": attr.label_list(
            allow_files = True,
        ),
        # The hugo executable
        "hugo": attr.label(
            default = "@hugo//:hugo",
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
        # Optionally set the base_url as a hugo argument
        "base_url": attr.string(),
        "theme": attr.label(
            providers = ["hugo_theme"],
        ),
        # Emit quietly
        "quiet": attr.bool(
            default = True,
        ),
        # Emit verbose
        "verbose": attr.bool(
            default = False,
        ),
    },
)
