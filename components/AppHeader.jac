"""Top bar: where you are, and what the graph currently holds."""

import from "@jac/runtime" { Link }

def:pub AppHeader(
    subtitle: str,
    crumb: str = "",
    children: any = None
) -> JsxElement {
    return <header className="hdr">
        <div className="hdr-left">
            <Link to="/" className="hdr-brand">
                <span className="hdr-glyph" aria-hidden="true"/>
                <span className="hdr-word">redact</span>
                <span className="hdr-word-dim">.graph</span>
            </Link>
            <span className="hdr-sep" aria-hidden="true">/</span>
            {if crumb {
                <Link to="/" className="hdr-crumb-link">library</Link>
                <span className="hdr-sep" aria-hidden="true">/</span>
                <span className="hdr-crumb">{crumb}</span>
            } else {
                <span className="hdr-crumb">library</span>
            }}
            <p className="hdr-sub">{subtitle}</p>
        </div>
        <div className="hdr-right">{children}</div>
    </header>;
}
