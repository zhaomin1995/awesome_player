/// Shared HTTP helper for the DLNA + AirPlay control planes.
///
/// Both AVTransport (UPnP) and AirPlay's RAOP-style HTTP commands wrap a
/// SOAP-ish XML body in a `text/xml` POST. Before this helper, DLNAManager
/// and AirPlayCastManager each open-coded the same URLRequest setup; the
/// only differences were the timeout and how each caller mapped the
/// response (Bool success vs raw Data). This module captures the shared
/// shape so we don't drift across the two callers if e.g. UPnP servers
/// stop accepting an empty SOAPACTION quote or we need a User-Agent header.
import Foundation

enum CastingHTTPClient {
    /// POST a SOAP AVTransport action to `controlURL`. Returns the response
    /// body + HTTP status code on the main queue, exactly once.
    ///
    /// Callers translate to their preferred result shape:
    ///   - DLNAManager wants `(Data?)` to parse <Track>/<Duration> XML.
    ///   - AirPlayCastManager wants a `Bool` for log-and-discard semantics.
    static func sendAVTransportAction(
        controlURL: String,
        action: String,
        body: String,
        timeout: TimeInterval = 10,
        completion: @escaping (_ data: Data?, _ statusCode: Int) -> Void
    ) {
        guard let url = URL(string: controlURL) else {
            DispatchQueue.main.async { completion(nil, 0) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(#""urn:schemas-upnp-org:service:AVTransport:1#\#(action)""#,
                         forHTTPHeaderField: "SOAPACTION")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = timeout

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { completion(data, code) }
        }.resume()
    }
}
