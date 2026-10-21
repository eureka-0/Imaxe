// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation

let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
let sourceNamespace = "https://github.com/eureka-0/Imaxe/appcast"
let retainedVersionCount = 7
let xmlReadOptions: XMLNode.Options = [.nodeLoadExternalEntitiesNever, .nodePreserveCDATA]

struct AppcastError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) {
    errorDescription = message
  }
}

func check(_ condition: Bool, _ message: String) throws {
  if !condition {
    throw AppcastError(message)
  }
}

func namespace(_ name: String, _ uri: String) throws -> XMLNode {
  guard let node = XMLNode.namespace(withName: name, stringValue: uri) as? XMLNode else {
    throw AppcastError("Unable to create XML namespace")
  }
  return node
}

func writeXML(_ document: XMLDocument, to url: URL) throws {
  var data = document.xmlData(options: .nodePrettyPrint)
  if data.last != 0x0A {
    data.append(0x0A)
  }
  try data.write(to: url, options: .atomic)
}

struct Record: Encodable {
  let tag: String
  let version: String
  let build: UInt64
  let commit: String
  let path: String

  init(_ path: String) throws {
    let document = try XMLDocument(
      contentsOf: URL(fileURLWithPath: path),
      options: xmlReadOptions,
    )
    let items = try document.nodes(forXPath: "/rss/channel/item")
    try check(items.count == 1, "History appcast must contain exactly one update: \(path)")
    guard let item = items.first as? XMLElement else { throw AppcastError("Missing update") }
    func value(_ name: String, _ namespace: String = sparkleNamespace) -> String {
      item.elements(forLocalName: name, uri: namespace).first?.stringValue ?? ""
    }
    version = value("shortVersionString")
    try check(
      version.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil,
      "Invalid marketing version",
    )
    guard let number = UInt64(value("version")),
          number > 0 else { throw AppcastError("Invalid build number") }
    build = number
    tag = "v\(version)"
    commit = value("sourceCommit", sourceNamespace)
    try check(
      commit.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
      "Missing or invalid source commit",
    )
    try check(value("channel").isEmpty, "Only stable updates belong in this feed")
    self.path = path
  }
}

struct Release: Decodable {
  struct Asset: Decodable { let name: String }
  let tag_name: String
  let draft: Bool
  let prerelease: Bool
  let assets: [Asset]
}

func catalog(history: String, releases: String) throws -> [Record] {
  let pages = try JSONDecoder().decode(
    [[Release]].self,
    from: Data(contentsOf: URL(fileURLWithPath: releases)),
  )
  var records: [Record] = []
  var builds: Set<UInt64> = []
  for release in pages.flatMap(\.self) where !release.draft && !release.prerelease {
    let tag = release.tag_name
    try check(
      tag.range(of: #"^v[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil,
      "Invalid stable release tag",
    )
    let zip = "Imaxe-\(tag.dropFirst()).zip"
    // v1.0.0 predates Sparkle and uses Imaxe.zip; it is not an update candidate.
    if !release.assets.contains(where: { $0.name == zip }) {
      continue
    }
    try check(
      release.assets.contains(where: { $0.name == "SHA256SUMS.txt" }),
      "Missing checksums for \(tag)",
    )
    let record = try Record("\(history)/\(tag)/appcast.xml")
    try check(record.tag == tag, "History version differs from release \(tag)")
    try check(builds.insert(record.build).inserted, "Duplicate stable build \(record.build)")
    records.append(record)
  }
  return records.sorted { $0.build > $1.build }
}

do {
  let args = Array(CommandLine.arguments.dropFirst())
  guard let command = args.first
  else { throw AppcastError("Expected stamp, catalog, merge, or newest") }
  switch command {
  case "stamp":
    try check(args.count == 3, "stamp <appcast.xml> <source-commit>")
    try check(
      args[2].range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
      "Invalid source commit",
    )
    let url = URL(fileURLWithPath: args[1])
    let document = try XMLDocument(contentsOf: url, options: xmlReadOptions)
    let items = try document.nodes(forXPath: "/rss/channel/item")
    try check(items.count == 1, "Stamp one release at a time")
    guard let root = document.rootElement(),
          let item = items.first as? XMLElement else { throw AppcastError("Invalid RSS") }
    try root.addNamespace(namespace("imaxe", sourceNamespace))
    for old in item.elements(forLocalName: "sourceCommit", uri: sourceNamespace) {
      old.detach()
    }
    let commit = XMLElement(name: "imaxe:sourceCommit", uri: sourceNamespace)
    commit.stringValue = args[2]
    item.addChild(commit)
    try writeXML(document, to: url)
  case "catalog", "merge":
    try check(
      args.count == (command == "catalog" ? 3 : 4),
      "\(command) <history-directory> <releases.json> [output.xml]",
    )
    let records = try catalog(history: args[1], releases: args[2])
    if command == "catalog" {
      try print(String(
        decoding: JSONEncoder().encode(Array(records.prefix(retainedVersionCount))),
        as: UTF8.self,
      ))
    } else {
      let root = XMLElement(name: "rss")
      guard let version = XMLNode.attribute(withName: "version", stringValue: "2.0") as? XMLNode
      else { throw AppcastError("Unable to create RSS version") }
      root.addAttribute(version)
      try root.addNamespace(namespace("sparkle", sparkleNamespace))
      try root.addNamespace(namespace("imaxe", sourceNamespace))
      let channel = XMLElement(name: "channel")
      channel.addChild(XMLElement(name: "title", stringValue: "Imaxe Updates"))
      channel.addChild(XMLElement(name: "link", stringValue: "https://github.com/eureka-0/Imaxe"))
      channel.addChild(XMLElement(name: "description", stringValue: "Stable Imaxe updates"))
      root.addChild(channel)
      for record in records.prefix(retainedVersionCount) {
        let source = try XMLDocument(
          contentsOf: URL(fileURLWithPath: record.path),
          options: xmlReadOptions,
        )
        guard let item = try source.nodes(forXPath: "/rss/channel/item").first
        else { throw AppcastError("Missing update") }
        item.detach()
        channel.addChild(item)
      }
      let document = XMLDocument(rootElement: root)
      document.characterEncoding = "UTF-8"
      try writeXML(document, to: URL(fileURLWithPath: args[3]))
    }
  case "newest":
    try check(args.count == 2, "newest <appcast.xml>")
    let document = try XMLDocument(
      contentsOf: URL(fileURLWithPath: args[1]),
      options: xmlReadOptions,
    )
    try check(document.nodes(forXPath: "/rss/channel").count == 1, "Invalid RSS channel")
    let items = try document.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
    try check(
      items.count <= retainedVersionCount,
      "Stable feed exceeds \(retainedVersionCount) updates",
    )
    let builds = try items.map { item -> UInt64 in
      guard let text = item.elements(forLocalName: "version", uri: sparkleNamespace).first?
        .stringValue,
        let build = UInt64(text), build > 0 else { throw AppcastError("Invalid public build") }
      return build
    }
    print(builds.max() ?? 0)
  default:
    throw AppcastError("Unknown command \(command)")
  }
} catch {
  FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
