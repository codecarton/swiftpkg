import Darwin
import SwiftPkgCore

exit(await SwiftPkg.run(arguments: Array(CommandLine.arguments.dropFirst())))
