# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Rules and macros for collecting LicenseInfo providers."""

load(
    "@rules_license//rules:providers.bzl",
    "LicenseInfo",
    "LicensesInfo",
)
load(":types.bzl", "types")

# MARK: - Debug

# Debugging verbosity
_VERBOSITY = 0

def _debug(loglevel, msg):
    if _VERBOSITY > loglevel:
        print(msg)  # buildifier: disable=print

def _add_debug(dbg, msg_or_fn):
    if _VERBOSITY == 0:
        return
    if types.is_function(msg_or_fn):
        msg = msg_or_fn()
    else:
        msg = msg_or_fn
    dbg.append(msg)

def _print_debug(dbg):
    if _VERBOSITY == 0:
        return
    print("\n".join(dbg))  # buildifier: disable=print

# MARK: - gather_licenses_info

_TARGET_TYPE = "Target"

def _is_target(val):
    return type(val) == _TARGET_TYPE

def _license_list_to_labels(license_list):
    if types.is_depset(license_list):
        licenses = license_list.to_list()
    else:
        licenses = license_list
    return [li.rule for li in licenses]

def _get_transitive_licenses_for_dep(dbg, dep, licenses, trans):
    _add_debug(dbg, lambda: "  depends on {}".format(dep.label))
    if LicenseInfo in dep:
        license = dep[LicenseInfo]
        _add_debug(dbg, lambda: "    with license {}".format(license.rule))
        licenses.append(license)
    if LicensesInfo in dep:
        license_list = dep[LicensesInfo].licenses
        if license_list:
            _add_debug(dbg, lambda: "    transitively depends on: {}".format(
                _license_list_to_labels(license_list),
            ))
            trans.append(license_list)

def _get_transitive_licenses_for_item(dbg, val, licenses, trans):
    if not _is_target(val):
        return
    _get_transitive_licenses_for_dep(dbg, val, licenses, trans)

def _get_transitive_licenses(dbg, val, licenses, trans):
    if types.is_list(val):
        for li in val:
            _get_transitive_licenses_for_item(dbg, li, licenses, trans)
    else:
        _get_transitive_licenses_for_item(dbg, val, licenses, trans)

def _gather_licenses_info_impl(target, ctx):
    licenses = []
    trans = []
    dbg = []
    _add_debug(dbg, lambda: "Gathering license info from {}".format(target))
    for attr in dir(ctx.rule.attr):
        val = getattr(ctx.rule.attr, attr)
        _get_transitive_licenses(dbg, val, licenses, trans)
    _print_debug(dbg)
    return [LicensesInfo(licenses = depset(tuple(licenses), transitive = trans))]

gather_licenses_info = aspect(
    doc = """Collects LicenseInfo providers into a single LicensesInfo provider.""",
    implementation = _gather_licenses_info_impl,
    attr_aspects = ["*"],
    apply_to_generating_rules = True,
)

# MARK: - write_licenses_info

def write_licenses_info(ctx, deps, json_out):
    """Writes LicensesInfo providers for a set of targets as JSON.

    TODO(aiuto): Document JSON schema.

    Usage:
      write_licenses_info must be called from a rule implementation, where the
      rule has run the gather_licenses_info aspect on its deps to collect the
      transitive closure of LicenseInfo providers into a LicenseInfo provider.

      foo = rule(
        implementation = _foo_impl,
        attrs = {
           "deps": attr.label_list(aspects = [gather_licenses_info])
        }
      )

      def _foo_impl(ctx):
        ...
        out = ctx.actions.declare_file("%s_licenses.json" % ctx.label.name)
        write_licenses_info(ctx, ctx.attr.deps, licenses_file)

    Args:
      ctx: context of the caller
      deps: a list of deps which should have LicensesInfo providers.
            This requires that you have run the gather_licenses_info
            aspect over them
      json_out: output handle to write the JSON info
    """

    rule_template = """  {{
    "rule": "{rule}",
    "license_kinds": [{kinds}
    ],
    "copyright_notice": "{copyright_notice}",
    "package_name": "{package_name}",
    "license_text": "{license_text}"\n  }}"""

    kind_template = """
      {{
        "target": "{kind_path}",
        "name": "{kind_name}",
        "conditions": {kind_conditions}
      }}"""

    licenses = []
    for dep in deps:
        if LicensesInfo in dep:
            for license in dep[LicensesInfo].licenses.to_list():
                _debug(0, "  Requires license: %s" % license)
                kinds = []
                for kind in license.license_kinds:
                    kinds.append(kind_template.format(
                        kind_name = kind.name,
                        kind_path = kind.label,
                        kind_conditions = kind.conditions,
                    ))
                licenses.append(rule_template.format(
                    rule = license.rule,
                    copyright_notice = license.copyright_notice,
                    package_name = license.package_name,
                    license_text = license.license_text.path,
                    kinds = ",\n".join(kinds),
                ))
    ctx.actions.write(
        output = json_out,
        content = "[\n%s\n]\n" % ",\n".join(licenses),
    )
