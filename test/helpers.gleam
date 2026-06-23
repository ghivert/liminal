import gleam/http
import liminal
import wisp.{type Response}
import wisp/simulate

pub fn call(
  router: liminal.Router,
  method: http.Method,
  path: String,
) -> Response {
  let handler = liminal.handler(router)
  let request = simulate.request(method, path)
  handler(request)
}

pub fn call_with_header(
  router: liminal.Router,
  method: http.Method,
  path: String,
  key: String,
  value: String,
) -> Response {
  let handler = liminal.handler(router)
  let request = simulate.request(method, path)
  let request = simulate.header(request, key, value)
  handler(request)
}
