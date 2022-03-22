@testable import CodableCSV
import XCTest

final class DialectDetectorTests: XCTestCase {
  func bufferAndDecoder(from string: String) -> (CSVReader.ScalarBuffer, CSVReader.ScalarDecoder) {
    let scalars = Array(string.unicodeScalars)
    let iter = scalars.makeIterator()
    let buffer = CSVReader.ScalarBuffer(reservingCapacity: 110)
    let decoder = CSVReader.makeDecoder(from: iter)
    return (buffer, decoder)
  }
}

// MARK: - Tests for detectDialect

extension DialectDetectorTests {
  func test_produceDialectCandidates() throws {
    let dialects = try DelimiterInferrer.produceDialectCandidates([",", ";"], [["\n"], ["\r"], ["\r\n"]])
    XCTAssertEqual(
      dialects,
      [
        try .init(field: ",", row: ["\n"]),
        try .init(field: ",", row: ["\r"]),
        try .init(field: ";", row: ["\n"]),
        try .init(field: ",", row: ["\r\n"]),
        try .init(field: ";", row: ["\r"]),
        try .init(field: ";", row: ["\r\n"]),
      ]
    )
  }
}

extension DialectDetectorTests {
  func test_detectDialect() throws {
    // Adapted from CPython
    // See: https://github.com/python/cpython/blob/f4c03484da59049eb62a9bf7777b963e2267d187/Lib/test/test_csv.py#L1039
    let dialects: [(String, (inout CSVReader.Configuration) -> Void, DelimiterInferrer.Dialect)] = [
      (
        """
        Harry's, Arlington Heights, IL, 2/1/03, Kimi Hayes
        Shark City, Glendale Heights, IL, 12/28/02, Prezence
        Tommy's Place, Blue Island, IL, 12/28/02, Blue Sunday/White Crow
        Stonecutters Seafood and Chop House, Lemont, IL, 12/19/02, Week Back
        """,
        { $0.escapingStrategy = .doubleQuote },
        try! DelimiterInferrer.Dialect(field: ",", row: "\n")
      ),
      (
        """
        'Harry''s':'Arlington Heights':'IL':'2/1/03':'Kimi Hayes'
        'Shark City':'Glendale Heights':'IL':'12/28/02':'Prezence'
        'Tommy''s Place':'Blue Island':'IL':'12/28/02':'Blue Sunday/White Crow'
        'Stonecutters ''Seafood'' and Chop House':'Lemont':'IL':'12/19/02':'Week Back'
        """,
        { $0.escapingStrategy = .scalar("'") },
        try! DelimiterInferrer.Dialect(field: ":", row: "\n")
      ),
      (
        """
        05/05/03?05/05/03?05/05/03?05/05/03?05/05/03?05/05/03
        05/05/03?05/05/03?05/05/03?05/05/03?05/05/03?05/05/03
        05/05/03?05/05/03?05/05/03?05/05/03?05/05/03?05/05/03
        """,
        { _ in },
        try! DelimiterInferrer.Dialect(field: "?", row: "\n")
      ),
    ]

    var configuration: CSVReader.Configuration
    for (csv, configurationSetter, expectedDialect) in dialects {
      configuration = .init()
      configurationSetter(&configuration)

      let detector = try DelimiterInferrer(configuration: configuration, possibleFieldDelimiters: ["?", "/", ",", ";", "\t", ":"], possibleRowDelimiters: [["\n"]])
//      let (buffer, decoder) = bufferAndDecoder(from: csv)
      let dialect = detector.detectDialect(from: Array(csv.unicodeScalars))
      XCTAssertEqual(dialect, expectedDialect, csv.debugDescription)
    }
  }
}

// MARK: - Tests for calculatePatternScore

extension DialectDetectorTests {
  // Adapted from CleverCSV
  // See: https://github.com/alan-turing-institute/CleverCSV/blob/master/tests/test_unit/test_detect_pattern.py#L160-L195
  func test_calculatePatternScore() throws {
    let dialectScores: [(DelimiterInferrer.Dialect, Double)] = [
      (try .init(field: ",", row: "\n"), 3.5 / 2),
//      (try .init(field: ";", row: "\n"), 10 / 3),
    ]
    let csv = #"""
      7,5; Mon, Jan 12;6,40
      100; Fri, Mar 21;8,23
      8,2; Thu, Sep 17;2,71
      538,0;;7,26
      "NA"; Wed, Oct 4;6,93
      """#
    // 4, 3, 4, 3, 3

    // 4: 2
    // 2 * (3 / 4) = 1.5
    // 3: 3
    // 3 * (2 / 3) = 2

    // (1.5 + 2) / 2 = 1.75

    // 3: 5
    // 5 * (2 / 3) / 1 = 4
    //


//    var score = 0.0
//    for (rowPattern, count) in rowPatternCounts {
//      let fieldCount = Double(rowPattern.split(separator: .fieldDelimiter).count)
//      score += Double(count) * max(Self.eps, fieldCount - 1.0) / fieldCount
//    }
//    score /= Double(rowPatternCounts.count)


    let inferrer = try DelimiterInferrer(possibleFieldDelimiters: [",", ";"], possibleRowDelimiters: [["\n"]])

    for (dialect, expectedScore) in dialectScores {
//      let (buffer, decoder) = bufferAndDecoder(from: csv)
      let abstraction = inferrer.makeAbstraction(from: Array(csv.unicodeScalars), using: dialect)

      let score = inferrer.calculatePatternScore(abstraction: abstraction)
      XCTAssertEqual(score, expectedScore, "Delimiter: \(dialect.field)")
    }
  }

  func test_calculatePatternScore_alt() throws {
    let fieldDelimiters: [Delimiter] = ["-", "--", "---"]
    let rowDelimiters: [Delimiter] = ["\n"]

    var configuration = CSVReader.Configuration()
    configuration.delimiters = (field: .infer(options: ["-","--", "---"]), row: .infer)

    let veryLongContent = Array(repeating: _TestData.longContent, count: 1).flatMap { $0 }

    for fieldDelimiter in fieldDelimiters {
      for rowDelimiter in rowDelimiters {
        let testString = _TestData.toCSV(veryLongContent, delimiters: (fieldDelimiter, rowDelimiter))

        let (buffer, decoder) = Self._TestData.bufferAndDecoder(from: testString)

        let inferrer = try DelimiterInferrer(configuration: configuration, possibleFieldDelimiters: ["-","--", "---"], possibleRowDelimiters: conf)
        XCTAssertEqual(delimiters, try! CSVReader.Settings.Delimiters(field: fieldDelimiter, row: rowDelimiter))
        //      let result = try CSVReader.decode(input: testString, configuration: configuration)
        //      XCTAssertEqual(result.rows, veryLongContent)
      }
    }
  }

  /// Demonstrates that it is useful to check for the correctness of the CSV
  /// that results from a particular dialect because there may be instances where
  /// two field delimiters both get a score of 1.0 despite one of them leading to
  /// a valid CSV and the other leading to a malformed CSV
  func test_calculatePatternScore_TieBreaking() throws {
//    let csv = """
//      foo;,bar
//      baz;,"boo"
//      """
    let csv = """
      05/05/03?05/05/03?05/05/03?05/05/03?05/05/03?05/05/03
      05/05/03?05/05/03?05/05/03?05/05/03?05/05/03?05/05/03
      05/05/03?05/05/03?05/05/03?05/05/03?05/05/03?05/05/03
      """

    let dialects: [(DelimiterInferrer.Dialect, Double)] = [
      (try .init(field: "?", row: "\n"), 1.0),
      (try .init(field: "/", row: "\n"), 0.5),
    ]

    let inferrer = try DelimiterInferrer(possibleFieldDelimiters: [",", ";"], possibleRowDelimiters: [["\n"]])

    for (dialect, expectedScore) in dialects {
      let msg = "Delimiter: \(dialect.field)"
      let abstraction = inferrer.makeAbstraction(from: Array(csv.unicodeScalars), using: dialect)!
      XCTAssertEqual(abstraction, [.cell, .fieldDelimiter, .cell, .rowDelimiter, .cell, .fieldDelimiter, .cell], msg)
      let score = inferrer.calculatePatternScore(abstraction: abstraction)
      XCTAssertEqual(score, expectedScore, msg)
    }
  }
}

// MARK: - Tests for makeAbstraction

extension DialectDetectorTests {
  func test_makeAbstraction() throws {
    let abstractions: [(String, [DelimiterInferrer.Abstraction])] = [
      ("", []),
      ("\n", []),
      ("\n\n", []),
      ("foo", [.cell]),

      (",", [.cell, .fieldDelimiter, .cell]),
      (",,", [.cell, .fieldDelimiter, .cell, .fieldDelimiter, .cell]),

      (",\n,", [.cell, .fieldDelimiter, .cell, .rowDelimiter, .cell, .fieldDelimiter, .cell]),
      (",foo\n,bar", [.cell, .fieldDelimiter, .cell, .rowDelimiter, .cell, .fieldDelimiter, .cell]),
    ]
    let dialect = try! DelimiterInferrer.Dialect(field: ",", row: ["\n"])
    let inferrer = try DelimiterInferrer(possibleFieldDelimiters: [",", ";"], possibleRowDelimiters: [["\n"]])

    for (csv, expected) in abstractions {
      let abstraction = inferrer.makeAbstraction(from: Array(csv.unicodeScalars), using: dialect)
      XCTAssertEqual(abstraction, expected, csv.debugDescription)
    }
  }

  func test_makeAbstraction_HandlesEscaping() throws {
    let escapingAbstractions: [(String, [DelimiterInferrer.Abstraction])] = [
      (#"  "foo",bar                     "#, [.cell, .fieldDelimiter, .cell]),
      (#"  "foo ""quoted"" \n ,bar",baz  "#, [.cell, .fieldDelimiter, .cell]),
      (#"  a,"bc""d""e""f""a",\n         "#, [.cell, .fieldDelimiter, .cell, .fieldDelimiter, .cell]),
    ]
    let dialect = try DelimiterInferrer.Dialect(field: ",", row: ["\n"])
    let inferrer = try DelimiterInferrer(possibleFieldDelimiters: [",", ";"], possibleRowDelimiters: [["\n"]])
    for (csv, expected) in escapingAbstractions {
      let strippedCSV = csv.trimmingCharacters(in: .whitespaces)
//      let (buffer, decoder) = bufferAndDecoder(from: strippedCSV)
      let abstraction = inferrer.makeAbstraction(from: Array(strippedCSV.unicodeScalars), using: dialect)
      XCTAssertEqual(abstraction, expected, csv.debugDescription)
    }
  }
}
