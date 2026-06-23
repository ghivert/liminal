import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleeunit
import helpers
import liminal
import wisp.{type Request, type Response}
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

// Basic routing

pub fn get_route_test() {
  let res =
    liminal.router()
    |> liminal.get(["hello"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Get, "/hello")
  assert res.status == 200
}

pub fn post_route_test() {
  let res =
    liminal.router()
    |> liminal.post(["hello"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Post, "/hello")
  assert res.status == 200
}

pub fn unknown_route_returns_404_test() {
  let res =
    liminal.router()
    |> liminal.get(["hello"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Get, "/unknown")
  assert res.status == 404
}

pub fn wrong_method_returns_default_test() {
  let res =
    liminal.router()
    |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Post, "/wobble")
  assert res.status == 404
}

pub fn first_registered_route_wins_test() {
  let res =
    liminal.router()
    |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
    |> liminal.get(["wobble"], fn(_, _) { wisp.response(418) })
    |> helpers.call(http.Get, "/wobble")
  assert res.status == 200
}

pub fn custom_default_handler_test() {
  let res =
    liminal.router()
    |> liminal.default(fn(_, _) { wisp.response(403) })
    |> helpers.call(http.Get, "/unknown")
  assert res.status == 403
}

// Redirects

pub fn redirect_test() {
  let res =
    liminal.router()
    |> liminal.get(["old"], liminal.redirect("new"))
    |> helpers.call(http.Get, "/old")
  assert res.status == 303
}

pub fn permanent_redirect_test() {
  let res =
    liminal.router()
    |> liminal.get(["old"], liminal.permanent_redirect("new"))
    |> helpers.call(http.Get, "/old")
  assert res.status == 308
}

// after middleware

fn stamp_header(res: Response, _params, next) -> Response {
  res |> response.prepend_header("x-ran", "yes") |> next
}

pub fn after_middleware_runs_test() {
  let res =
    liminal.router()
    |> liminal.after(stamp_header)
    |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Get, "/wobble")
  assert list.key_find(res.headers, "x-ran") == Ok("yes")
}

// Exposes bug: after middleware on parent router is bypassed for sub-router routes
pub fn after_middleware_runs_on_subrouter_routes_test() {
  let res =
    liminal.router()
    |> liminal.after(stamp_header)
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
    })
    |> helpers.call(http.Get, "/wobble/wibble")
  assert list.key_find(res.headers, "x-ran") == Ok("yes")
}

// before middleware

fn require_auth(req: Request, _params, next) -> Response {
  case list.key_find(req.headers, "authorization") {
    Error(_) -> wisp.response(401)
    Ok(_) -> next(req)
  }
}

pub fn before_middleware_blocks_unauthenticated_test() {
  let res =
    liminal.router()
    |> liminal.before(require_auth)
    |> liminal.get(["protected"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Get, "/protected")
  assert res.status == 401
}

pub fn before_middleware_allows_authenticated_test() {
  let res =
    liminal.router()
    |> liminal.before(require_auth)
    |> liminal.get(["protected"], fn(_, _) { wisp.ok() })
    |> helpers.call_with_header(
      http.Get,
      "/protected",
      "authorization",
      "token",
    )
  assert res.status == 200
}

pub fn before_middleware_on_parent_applies_to_subrouter_routes_test() {
  let res =
    liminal.router()
    |> liminal.before(require_auth)
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
    })
    |> helpers.call(http.Get, "/wobble/wibble")
  assert res.status == 401
}

pub fn before_middleware_on_parent_and_subrouter_run_in_order_test() {
  // Parent's before runs first (outer), sub-router's before runs second (inner)
  let append = fn(a) {
    fn(req: Request, _params, next) {
      let trace = list.key_find(req.headers, "x-trace") |> result.unwrap("")
      req |> request.set_header("x-trace", trace <> a) |> next
    }
  }
  let append_a = append("a")
  let append_b = append("b")
  let res =
    liminal.router()
    |> liminal.before(append_a)
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.before(append_b)
      |> liminal.get(["wibble"], fn(req: Request, _) {
        case list.key_find(req.headers, "x-trace") {
          Ok(trace) -> wisp.json_response(trace, 200)
          Error(_) -> wisp.response(500)
        }
      })
    })
    |> helpers.call(http.Get, "/wobble/wibble")
  assert simulate.read_body(res) == "ab"
}

pub fn multiple_before_middlewares_run_in_order_test() {
  let append = fn(a) {
    fn(req: Request, _params, next) {
      let trace = list.key_find(req.headers, "x-trace") |> result.unwrap("")
      req |> request.set_header("x-trace", trace <> a) |> next
    }
  }
  let append_a = append("a")
  let append_b = append("b")
  let res =
    liminal.router()
    |> liminal.before(append_a)
    |> liminal.before(append_b)
    |> liminal.get(["wobble"], fn(req: Request, _) {
      case list.key_find(req.headers, "x-trace") {
        Ok(trace) -> wisp.json_response(trace, 200)
        Error(_) -> wisp.response(500)
      }
    })
    |> helpers.call(http.Get, "/wobble")
  assert simulate.read_body(res) == "ab"
}

pub fn multiple_after_middlewares_run_in_order_test() {
  let append = fn(a) {
    fn(res: Response, _params, next) {
      let trace = response.get_header(res, "x-trace") |> result.unwrap("")
      res |> response.set_header("x-trace", trace <> a) |> next
    }
  }
  let append_a = append("a")
  let append_b = append("b")
  let res =
    liminal.router()
    |> liminal.after(append_a)
    |> liminal.after(append_b)
    |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
    |> helpers.call(http.Get, "/wobble")
  assert response.get_header(res, "x-trace") == Ok("ab")
}

// Exposes bug: before middleware on sub-router runs twice per request
pub fn before_middleware_runs_once_on_subrouter_routes_test() {
  let count_calls = fn(req: Request, _params, next) {
    req
    |> request.prepend_header("x-count", "1")
    |> next
  }
  let res =
    liminal.router()
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.before(count_calls)
      |> liminal.get(["wibble"], fn(req: Request, _) {
        req.headers
        |> list.count(fn(h) { h.0 == "x-count" })
        |> int.to_string
        |> wisp.json_response(200)
      })
    })
    |> helpers.call(http.Get, "/wobble/wibble")
  assert simulate.read_body(res) == "1"
}

// context / sub-router

pub fn context_routes_to_subrouter_test() {
  let res =
    liminal.router()
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
    })
    |> helpers.call(http.Get, "/wobble/wibble")
  assert res.status == 200
}

pub fn context_path_params_test() {
  let res =
    liminal.router()
    |> liminal.context(at: [":id"], router: {
      liminal.router()
      |> liminal.get(["info"], fn(_req, params) {
        case dict.get(params, "id") {
          Ok(id) -> wisp.json_response(id, 200)
          Error(_) -> wisp.response(500)
        }
      })
    })
    |> helpers.call(http.Get, "/42/info")
  assert simulate.read_body(res) == "42"
}

pub fn context_post_params_test() {
  let res =
    liminal.router()
    |> liminal.context(at: ["example", ":id"], router: {
      liminal.router()
      |> liminal.post(["thing"], fn(_req, params) {
        params
        |> dict.to_list
        |> list.map(pair.map_second(_, json.string))
        |> json.object
        |> json.to_string
        |> wisp.json_response(200)
      })
    })
    |> helpers.call_with_header(
      http.Post,
      "/example/dummy/thing",
      "authorization",
      "test",
    )
  let expected = json.object([#("id", json.string("dummy"))]) |> json.to_string
  assert simulate.read_body(res) == expected
}

pub fn context_inherits_parent_default_handler_test() {
  let res =
    liminal.router()
    |> liminal.default(fn(_, _) { wisp.response(403) })
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
    })
    |> helpers.call(http.Get, "/wobble/unknown")
  assert res.status == 403
}

pub fn context_uses_own_default_handler_test() {
  let res =
    liminal.router()
    |> liminal.default(fn(_, _) { wisp.response(403) })
    |> liminal.context(at: ["wobble"], router: {
      liminal.router()
      |> liminal.default(fn(_, _) { wisp.response(418) })
      |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
    })
    |> helpers.call(http.Get, "/wobble/unknown")
  assert res.status == 418
}
