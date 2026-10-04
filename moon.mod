// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "zlhahaha/partsieve"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ ]

preferred_target = "native"

description = "OOXML capability audit and verified rebuild; restricted XLSM spike"

import {
  "moonbit-community/flate@0.8.4",
  "Milky2018/xml@0.5.0",
  "moonbitlang/x@0.5.5",
}
