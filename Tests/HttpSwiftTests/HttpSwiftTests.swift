//
//  Tests.swift
//  HttpSwiftTests
//
//  Created by Orkhan Alikhanov on 7/4/17.
//  Copyright © 2017 BiAtoms. All rights reserved.
//

import XCTest
import SocketSwift
import RequestSwift

@testable import HttpSwift
typealias Request = HttpSwift.Request
typealias Response = HttpSwift.Response


class HttpSwiftTests: XCTestCase {
    
    struct a {
        static let server: Server = {
            let server = Server()
            server.run()
            return server
        }()
        static let client = Client(baseUrl: "http://localhost:8080")
    }
    
    var port = Port(8080)
    var server: Server {
        return a.server
    }
    var client: Client {
        return a.client
    }
    
    func testRoute() {
        let route = Route(method: "", path: "/api/{param1}/{param2}/next/{param3}", handler: {_ in return Response(.ok, body: [])})
        XCTAssertEqual(route.paramNames, ["param1", "param2", "param3"])
        
        let pattern = "(.+)\\/?"
        XCTAssertEqual(route.regexPattern, "\\/api\\/\(pattern)\\/\(pattern)\\/next\\/\(pattern)")
    }
    
    func testRequestAndResponse() {
        let data = "Hello World"
        let queryParams = ["string": "salam əıoueəiöü",
                           "number": "123"]
        let responseString = "TestPassed"
        let ex = expectation(description: "test")
        server.post("/hello/{id}/{name}/next/{part}") { request in
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.path, "/hello/23/hi/next/second")
            XCTAssertEqual(request.routeParams, ["id": "23", "name": "hi", "part": "second"])
            XCTAssertEqual(request.queryParams, queryParams)
            XCTAssertTrue(request.headers.contains([
                "Host": "localhost:8080",
                "Content-Type": "text/plain",
                "Content-Length": "\(data.bytes.count)"
                ]))
            XCTAssertEqual(request.body, data.bytes)
            return .ok(responseString)
        }
        
        client.request("/hello/23/hi/next/second",
                       method: .post,
                       parameters: queryParams, encoding: data,
                       headers: ["Content-Type": "text/plain"]).responseString { r in
                        
                        XCTAssertTrue(r.response!.contains(["Server": "Http.swift"]))
                        XCTAssertEqual(r.value, responseString)
                        ex.fulfill()
        }
        
        waitForExpectations()
    }
    
    func testResponseExceptions() {
        let ex = expectation(description: "httpRouteNotDefined")
        client.request("/aNonDefinedRoute").response { response, _ in
            XCTAssertEqual(response?.statusCode, 404)
            ex.fulfill()
        }
        waitForExpectations()
    }
    
    func testErrorHandler() {
        let ex = expectation(description: "httpRouteNotDefined")
        server.errorHandler = MyErrorHandler.self
        client.request("/aNonDefinedRoute").responseString { r in
            XCTAssertEqual(r.response?.statusCode, 200)
            XCTAssertEqual(r.value, "Error is handled")
            self.server.errorHandler = ErrorHandler.self
            ex.fulfill()
        }
        waitForExpectations()
    }
    
    class MyErrorHandler: ErrorHandler {
        override class func onError(request: Request?, error: Error) -> Response? {
            if let error = error as? ServerError {
                if error == .httpRouteNotFound {
                    return Response(.ok, body: "Error is handled")
                }
            }
            
            return super.onError(request: request, error: error)
        }
    }
    
    func testMiddleware() {
        func Req(_ str: String) -> MiddlewareHandler {
            return { request, closure in
                request.headers["middleware"] = (request.headers["middleware"] ?? "") + str
                return try closure(request)
            }
        }
        
        func Res(_ str: String) -> MiddlewareHandler {
            return { request, closure in
                let response = try closure(request)
                response.headers["middleware"] = (response.headers["middleware"] ?? "") + str
                return response
            }
        }
        
        server.middlewares = [Req("1"), Req("2"), Req("3"), Res("A"), Res("B"), Res("C")]
        let url = "/testMiddleware"
        server.get(url) { request in
            XCTAssertTrue(request.headers.contains(["middleware": "123"]))
            self.server.middlewares = []
            return .ok("passed")
        }
        
        let ex = expectation(description: "ext")
        client.request(url).responseString { r in
            XCTAssert(r.response!.contains(["middleware": "CBA"]))
            ex.fulfill()
        }
        
        waitForExpectations()
        
        //changing order
        server.middlewares = [Res("A"), Req("1"), Req("2"), Req("3"), Res("B"), Res("C")]
        let url2 = "/testMiddleware2"
        server.get(url2) { request in
            XCTAssertTrue(request.headers.contains(["middleware": "123"]))
            self.server.middlewares = []
            return .ok("passed")
        }
        
        let ex2 = expectation(description: "ext")
        client.request(url2).responseString { r in
            XCTAssert(r.response!.contains(["middleware": "CBA"]))
            ex2.fulfill()
        }
        
        waitForExpectations()
    }
    
    static var allTests = [
        ("testRoute", testRoute),
        ("testRequestAndResponse", testRequestAndResponse),
        ("testResponseExceptions", testResponseExceptions),
        ("testErrorHandler", testErrorHandler),
        ("testMiddleware", testMiddleware),
        ]
    
}

extension String: ParameterEncoding {
    public func encode(_ request: RequestSwift.Request, with parameters: Parameters?) {
        URLEncoding.queryString.encode(request, with: parameters)
        request.body = self.bytes
    }
}

extension Dictionary where Value: Equatable {
    func contains(_ other: Dictionary<Key, Value>) -> Bool {
        for key in other.keys {
            if !self.keys.contains(key) || self[key]! != other[key]! {
                return false
            }
        }
        return true
    }
}


extension RequestSwift.Response {
    func contains(_ headers: [String:String]) -> Bool {
        return self.headers.reduce([String:String]()) {
            var a = $0
            a[$1.key] = $1.value
            return a
            }.contains(headers)
    }
}

extension XCTestCase {
    func waitForExpectations() {
        waitForExpectations(timeout: 1)
    }
}

extension Requester {
    typealias ResponseString = (value: String, response: RequestSwift.Response?, error: Error?)
    func responseString(_ handlr: @escaping ( (ResponseString) -> Void)) {
        let h: ResponseHandler = { (res: RequestSwift.Response?, error: Error?) in
            let bytes = res?.body ?? [UInt8]()
            handlr((String(data: Data(bytes: bytes, count: bytes.count), encoding: .utf8)!, res, error))
        }
        self.response(h)
    }
}
