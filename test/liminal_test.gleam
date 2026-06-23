import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/list
import gleam/pair
import gleeunit
import liminal
import mist
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn router_test() {
  let assert Ok(_server) = start_server()
  test_get_request("/example", 303, "You are being redirected: localhost")
  test_get_request("/wobble", 200, "OK")
  test_get_request("/wibble", 200, "OK")
  test_post_request("/wibble", 200, "OK")
  test_get_request("/wibble-wobble", 403, "Forbidden")
  test_get_request("/not-found", 404, "Not found")
  test_get_request("/example/dummy", 400, "Bad request: Unauthorized")
  test_auth_get_request("/example/dummy", 403, "Forbidden")
  let res = json.object([#("id", json.string("dummy"))])
  test_post_request("/example/dummy/thing/thing", 200, json.to_string(res))
}

fn start_server() {
  let secret_key = wisp.random_string(24)
  test_router()
  |> liminal.handler
  |> wisp_mist.handler(secret_key)
  |> mist.new
  |> mist.bind("localhost")
  |> mist.port(3300)
  |> mist.start
}

fn test_router() {
  liminal.router()
  |> liminal.after(compress_messages)
  |> liminal.default(default_forbidden)
  |> liminal.get(["example"], liminal.redirect("localhost"))
  |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
  |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
  |> liminal.get(["wibble"], fn(_, _) { wisp.not_found() })
  |> liminal.post(["wibble"], fn(_, _) { wisp.ok() })
  |> liminal.post(["wobble"], fn(_, _) { wisp.bad_request("Not allowed") })
  |> liminal.context(at: ["not-found"], router: empty_router())
  |> liminal.context(at: ["example", ":id"], router: {
    liminal.router()
    |> liminal.before(prevent_non_logged_users)
    |> liminal.get(["static", "success"], liminal.proxy("http://localhost"))
    |> liminal.get(["static", "error"], liminal.proxy("http://localhost"))
    |> liminal.get(["code", "microsoft"], liminal.proxy("http://localhost"))
    |> liminal.get(["code", "google"], liminal.proxy("http://localhost"))
    |> liminal.post(["thing", "thing"], fn(_req, params) {
      dict.to_list(params)
      |> list.map(pair.map_second(_, json.string))
      |> json.object
      |> json.to_string
      |> wisp.json_response(200)
    })
  })
}

fn default_forbidden(_, _) {
  let body = wisp.Text("Forbidden")
  wisp.response(403)
  |> wisp.set_body(body)
}

fn empty_router() {
  let default_handler = fn(_, _) { wisp.not_found() }
  liminal.router()
  |> liminal.default(default_handler)
}

fn test_get_request(to to, status status, expect expect) {
  let assert Ok(req) = request.to("http://localhost:3300" <> to)
  let assert Ok(res) = httpc.send(req)
  assert res.status == status as to
  assert res.body == expect as to
}

fn test_auth_get_request(to to, status status, expect expect) {
  let assert Ok(req) = request.to("http://localhost:3300" <> to)
  let req = request.set_header(req, "authorization", "test")
  let assert Ok(res) = httpc.send(req)
  assert res.status == status as to
  assert res.body == expect as to
}

fn test_post_request(to to, status status, expect expect) {
  let assert Ok(req) = request.to("http://localhost:3300" <> to)
  let req = request.set_method(req, http.Post)
  let req = request.set_header(req, "authorization", "test")
  let assert Ok(res) = httpc.send(req)
  assert res.status == status
  assert res.body == expect
}

fn prevent_non_logged_users(req: Request, _params, next) -> Response {
  case list.key_find(req.headers, "authorization") {
    Error(_) -> wisp.bad_request("Unauthorized")
    Ok(content) if content != "test" -> wisp.bad_request("Unauthorized")
    Ok(_content) -> next(req)
  }
}

fn compress_messages(res: Response, _params, next) -> Response {
  res
  |> response.prepend_header("user-agent", "gleeunit")
  |> next
}
