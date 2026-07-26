"""A labelled number. The whole UI is counts off the graph, so this repeats."""

def:pub MetaChip(label: str, value: str, tone: str = "neutral") -> JsxElement {
    return <span className={"chip chip-" + tone}>
        <span className="chip-label">{label}</span>
        <span className="chip-value">{value}</span>
    </span>;
}
