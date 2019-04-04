
load("@protobuf_archive//:protobuf.bzl", "proto_gen")

def _proto_cc_hdrs(srcs, use_grpc_plugin=False):
  ret = [s[:-len(".proto")] + ".pb.h" for s in srcs]
  if use_grpc_plugin:
    ret += [s[:-len(".proto")] + ".grpc.pb.h" for s in srcs]
  return ret

def _proto_cc_srcs(srcs, use_grpc_plugin=False):
  ret = [s[:-len(".proto")] + ".pb.cc" for s in srcs]
  if use_grpc_plugin:
    ret += [s[:-len(".proto")] + ".grpc.pb.cc" for s in srcs]
  return ret

#
# Re-defined protocol buffer rule to allow building "header only" protocol
# buffers, to avoid duplicate registrations. Also allows non-iterable cc_libs
# containing select() statements.
def cc_proto_library(
    name,
    srcs=[],
    deps=[],
    cc_libs=[],
    include=None,
    protoc="@protobuf_archive//:protoc",
    internal_bootstrap_hack=False,
    use_grpc_plugin=False,
    default_header=False,
    **kargs):
  """Bazel rule to create a C++ protobuf library from proto source files.

  Args:
    name: the name of the cc_proto_library.
    srcs: the .proto files of the cc_proto_library.
    deps: a list of dependency labels; must be cc_proto_library.
    cc_libs: a list of other cc_library targets depended by the generated
        cc_library.
    include: a string indicating the include path of the .proto files.
    protoc: the label of the protocol compiler to generate the sources.
    internal_bootstrap_hack: a flag indicate the cc_proto_library is used only
        for bootstraping. When it is set to True, no files will be generated.
        The rule will simply be a provider for .proto files, so that other
        cc_proto_library can depend on it.
    use_grpc_plugin: a flag to indicate whether to call the grpc C++ plugin
        when processing the proto files.
    default_header: Controls the naming of generated rules. If True, the `name`
        rule will be header-only, and an _impl rule will contain the
        implementation. Otherwise the header-only rule (name + "_headers_only")
        must be referred to explicitly.
    **kargs: other keyword arguments that are passed to cc_library.
  """

  includes = []
  if include != None:
    includes = [include]

  if internal_bootstrap_hack:
    # For pre-checked-in generated files, we add the internal_bootstrap_hack
    # which will skip the codegen action.
    proto_gen(
        name=name + "_genproto",
        srcs=srcs,
        deps=[s + "_genproto" for s in deps],
        includes=includes,
        protoc=protoc,
        visibility=["//visibility:public"],
    )
    # An empty cc_library to make rule dependency consistent.
    native.cc_library(
        name=name,
        **kargs)
    return

  grpc_cpp_plugin = None
  if use_grpc_plugin:
    grpc_cpp_plugin = "//external:grpc_cpp_plugin"

  gen_srcs = _proto_cc_srcs(srcs, use_grpc_plugin)
  gen_hdrs = _proto_cc_hdrs(srcs, use_grpc_plugin)
  outs = gen_srcs + gen_hdrs

  proto_gen(
      name=name + "_genproto",
      srcs=srcs,
      deps=[s + "_genproto" for s in deps],
      includes=includes,
      protoc=protoc,
      plugin=grpc_cpp_plugin,
      plugin_language="grpc",
      gen_cc=1,
      outs=outs,
      visibility=["//visibility:public"],
  )

  if use_grpc_plugin:
    cc_libs += ["//external:grpc_lib"]

  if default_header:
    header_only_name = name
    impl_name = name + "_impl"
  else:
    header_only_name = name + "_headers_only"
    impl_name = name

  native.cc_library(
      name=impl_name,
      srcs=gen_srcs,
      hdrs=gen_hdrs,
      deps=cc_libs + deps,
      includes=includes,
      **kargs)
  native.cc_library(
      name=header_only_name,
      deps=["@protobuf_archive//:protobuf_headers"],
      hdrs=gen_hdrs,
      **kargs)


def brpc_proto_library(name, srcs, deps=[], include=None, visibility=None, testonly=0):
    native.filegroup(name=name + "_proto_srcs",
                     srcs=srcs,
                     visibility=visibility,)
    cc_proto_library(name=name,
                     srcs=srcs,
                    deps=deps,
cc_libs=["@protobuf_archive//:protobuf_headers"],
                     include=include,
                     protoc="@protobuf_archive//:protoc",
                     testonly=testonly,
    default_header=False,
                     visibility=visibility,)

