// Parts of the code in this file are adapted from the CleverCSV Python library.
// See: https://github.com/alan-turing-institute/CleverCSV

/*
 Copyright (c) 2018 The Alan Turing Institute

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import Foundation

/// Provides the means for detecting a CSV file's dialect
enum DialectDetector {
	private static let fieldDelimiters: [Unicode.Scalar] = [",", ";", "\t", "|"]

	/// Detects the dialect used in the provided CSV file.
	///
	///	A dialect describes the way in which a CSV file is formatted, i.e. which field
	///	delimiter, row delimiter and escape character is used.
	///
	/// - Parameter stringScalars: The raw CSV data.
	/// - Returns: The detected dialect.
	static func detectDialect(stringScalars: [UnicodeScalar]) -> Dialect {
		let dialects = fieldDelimiters.map { Dialect(fieldDelimiter: $0) }

		var maxConsistency = -Double.infinity
		var scores: [Dialect: Double] = [:]

		// TODO: Sort dialects from most to least probable?
		for dialect in dialects {
			let patternScore = calculatePatternScore(stringScalars: stringScalars, dialect: dialect)

			if patternScore < maxConsistency {
				// Skip the computation of the type score for dialects with a low pattern score.
				continue
			}
			// TODO: Calculate type score?
			let typeScore = 1.0
			let consistencyScore = patternScore * typeScore
			maxConsistency = max(maxConsistency, consistencyScore)
			scores[dialect] = consistencyScore
		}

		let best = scores.max { a, b in a.value < b.value }

		return best?.key ?? Dialect(fieldDelimiter: ",")
	}

	private static let eps = 0.001

	/// Calculates a score for the given dialect by anayzing the row patterns that result when interpreting the CSV data using that dialect.
	///
	/// The correct dialect is expected to produce many rows of the same pattern
	/// The pattern score favors row patterns that occur often, that are long and favors having fewer row patterns.
	///
	/// - parameter stringScalars: The raw CSV data.
	/// - parameter dialect: A dialect for which to calculate the score.
	/// - returns: The calculated pattern score for the given dialect.
	static func calculatePatternScore(stringScalars: [UnicodeScalar], dialect: Dialect) -> Double {
		let (abstractions, _) = makeAbstraction(stringScalars: stringScalars, dialect: dialect)

		#warning("TODO: Break ties based on generated errors")

		let rowPatternCounts: [ArraySlice<Abstraction>: Int] = abstractions
			.split(separator: .rowDelimiter)
			.occurenceCounts()

		var score = 0.0
		for (rowPattern, count) in rowPatternCounts {
			let fieldCount = Double(rowPattern.split(separator: .fieldDelimiter).count)
			score += Double(count) * max(eps, fieldCount - 1.0) / fieldCount
		}
		score /= Double(rowPatternCounts.count)

		return score
	}

	/// Describes a CSV file's formatting.
	struct Dialect: Hashable {
		let fieldDelimiter: Unicode.Scalar
		let rowDelimiter: Unicode.Scalar = "\n"
		let escapeCharacter: Unicode.Scalar = "\""
	}
}

// MARK: -

extension DialectDetector {
	/// An abstracted piece of CSV data
	enum Abstraction: Character, Hashable {
		case cell = "C", fieldDelimiter = "D", rowDelimiter = "R"

		/// The type of error raised by `makeAbstraction`.
		enum Error: Swift.Error {
			/// An escape character, e.g. a quote, occured in an invalid place.
			///
			/// Example:
			/// ```
			/// foo,bar"wrong",baz
			/// ```
			case invalidEscapeCharacterPosition

			/// The last escaped field was not closed due to an uneven number of escape characters.
			///
			/// Example:
			/// ```
			/// foo,bar,"baz
			/// ```
			case unbalancedEscapeCharacters
		}
	}

	/// Builds an abstraction of the CSV data by parsing it with the provided dialect.
	///
	/// For example, consider the following CSV data:
	/// ```
	/// one,two,three
	/// foo,funny ;),bar
	/// ```
	/// Assuming a field delimiter of `,` this produces the following abstraction:
	/// ```
	/// CDCDC
	/// CDCDC
	/// ```
	/// Here, `C` represents a cell (field) and `D` stands for a field delimiter.
	///
	/// However when we instead consider `;` as the field delimiter, the following abstraction is produced:
	/// ```
	/// C
	/// CDC
	/// ```
	/// This abstraction can then be used to guess the delimiter, because the correct
	/// delimiter will produce an abstraction with many identical row patterns.
	///
	/// - parameter stringScalars: The raw CSV data.
	/// - parameter dialect: The dialect to use for speculatively interpreting the CSV data.
	/// - throws: An `Abstraction.Error`.
	/// - returns: An array of cells and delimiters.
	/// - todo: Currently assuming that delimiters can only be made up of a single Unicode scalar.
	static func makeAbstraction(stringScalars: [Unicode.Scalar], dialect: Dialect) -> ([Abstraction], [Abstraction.Error]) {
		var abstraction: [Abstraction] = []
		var errors: [Abstraction.Error] = []
		var escaped = false

		var iter = stringScalars.makeIterator()
		var queuedNextScalar: Unicode.Scalar? = nil
		while true {
			guard let scalar = queuedNextScalar ?? iter.next() else { break }
			queuedNextScalar = nil

			switch scalar {
			case dialect.fieldDelimiter:
				if escaped { continue }

				switch abstraction.last {
				// - two consecutive field delimiters OR
				// - field delimiter after row delimiter, i.e. at start of line OR
				// - field delimiter at the very beginning, i.e. at start of first line
				// all imply an empty cell
				case .fieldDelimiter, .rowDelimiter, nil:
					abstraction.append(.cell)
					fallthrough
				case .cell:
					abstraction.append(.fieldDelimiter)
				}

			case dialect.rowDelimiter:
				if escaped { continue }

				switch abstraction.last {
				// - two consecutive row delimiters
				// - row delimiter after field delimiter
				// - row delimiter at the very beginning, i.e. at start of first line
				// all imply an empty cell
				case .rowDelimiter, .fieldDelimiter, nil:
					abstraction.append(.cell)
					fallthrough
				case .cell:
					abstraction.append(.rowDelimiter)
				}

			case dialect.escapeCharacter:
				if !escaped {
					if abstraction.last == .cell {
						// encountered an escape character after the beginning of a field
						errors.append(.invalidEscapeCharacterPosition)
					}
					escaped = true
					continue
				}

				// we are in an escaped context, so the encountered escape character
				// is either the end of the field or must be followed by another escape character
				let nextScalar = iter.next()

				switch nextScalar {
				case dialect.escapeCharacter:
					// the escape character was escaped
					continue
				case nil:
					// end of file
					escaped = false
				case dialect.fieldDelimiter, dialect.rowDelimiter:
					// end of field
					escaped = false
					queuedNextScalar = nextScalar
				default:
					// encountered a non-delimiter character after the field ended
					errors.append(.invalidEscapeCharacterPosition)
					escaped = false
					queuedNextScalar = nextScalar
				}

			default:
				switch abstraction.last {
				case .cell:
					continue
				case .fieldDelimiter, .rowDelimiter, nil:
					abstraction.append(.cell)
				}
			}
		}

		if abstraction.last == .fieldDelimiter {
			abstraction.append(.cell)
		}

		if escaped {
			// reached EOF without closing the last escaped field
			errors.append(.unbalancedEscapeCharacters)
		}

		return (abstraction, errors)
	}
}

// MARK: -

extension DialectDetector {
	/// A representation of a CSV field's data type.
	enum FieldType: CaseIterable {
		case currency, date, empty, notAvailable, number, url, uuid

		var check: (String) -> Bool {
			switch self {
			case .currency:
				return { _ in false }
			case .date:
				return { NSDataDetector(type: .date).completelyMatches($0) }
			case .empty:
				return { $0.isEmpty }
			case .notAvailable:
				return { ["n/a", "na"].contains($0.lowercased()) }
			case .number:
				return { Double($0) != nil }
			case .url:
				return { NSDataDetector(type: .link).completelyMatches($0) }
			case .uuid:
				return { UUID(uuidString: $0) != nil }
			}
		}
	}

	/// Tries to detect the data type of a CSV field.
	/// - parameter string: The field's contents.
	/// - returns: The detected type, or `nil` if no type could be detected.
	static func detectType(of string: String) -> FieldType? {
		for fieldType in FieldType.allCases {
			if fieldType.check(string) {
				return fieldType
			}
		}

		return nil
	}

	/// Tries to detect whether an abstract CSV representation has a header row.
	/// - parameter abstractRows: The abstract representation of the CSV file.
	/// - returns: `true` if we're confident that there _is_ a header row. `false` if we're confident that there is _no_ header row. `nil` if we don't know.
	static func isHeaderPresent(in abstractRows: [[FieldType?]]) -> Bool? {
		if abstractRows.count == 0 {
			return false
		}

		if abstractRows[0].contains(where: isDetectedType) {
			return false
		}

		if abstractRows.allSatisfy({ row in row.allSatisfy(isUndetectedType) }) {
			return nil
		}

		if
			abstractRows[0].allSatisfy(isUndetectedType),
			abstractRows[1].contains(where: isDetectedType),
			abstractRows[1...].allEqual()
		{
			return true
		}

		return nil
	}
}

private let isUndetectedType: (DialectDetector.FieldType?) -> Bool = { $0 == nil }
private let isDetectedType: (DialectDetector.FieldType?) -> Bool = { $0 != nil }

private extension NSDataDetector {
	convenience init(type: NSTextCheckingResult.CheckingType) {
		try! self.init(types: type.rawValue)
	}

	/// Checks whether the entire string matches the data detector's conditions.
	/// - Parameter string: The string to match.
	/// - Returns: `true` if the entire string matched. Otherwise `false`.
	func completelyMatches(_ string: String) -> Bool {
		let matches = self.matches(in: string, range: string.nsRange)

		guard matches.count == 1
		else { return false }

		return matches[0].range == string.nsRange
	}
}

private extension String {
	var nsRange: NSRange {
		.init(location: 0, length: self.count)
	}
}
