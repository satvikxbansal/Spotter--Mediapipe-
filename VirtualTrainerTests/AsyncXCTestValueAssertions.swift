import XCTest

func assertTrue(
    _ expression: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(expression, message(), file: file, line: line)
}

func assertFalse(
    _ expression: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(expression, message(), file: file, line: line)
}

func assertEqual<T: Equatable>(
    _ expression1: T,
    _ expression2: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

func unwrap<T>(
    _ expression: T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    try XCTUnwrap(expression, message(), file: file, line: line)
}
