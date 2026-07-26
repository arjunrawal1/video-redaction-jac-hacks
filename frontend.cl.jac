"""Client shell: the route table, and nothing else.

Manual routing (no `pages/` directory), so navigation is `<Link>` all the way
down and a frame selection is a URL, not a call: /video/<id>/frame/<n> is
shareable and survives a reload. Each page below owns its own state.
"""

import from "@jac/runtime" { Router, Routes, Route, Navigate, useParams }
import from .components.LibraryPage { LibraryPage }
import from .components.StudioPage { StudioPage }

"""A video with no frame in the URL means frame 1."""
def VideoEntry -> JsxElement {
    params = useParams();
    if not params["id"] {
        return <Navigate to="/" replace={True}/>;
    }
    video_id: str = str(params["id"]);
    return <Navigate to={f"/video/{video_id}/frame/1"} replace={True}/>;
}

def:pub app -> JsxElement {
    return <Router>
        <Routes>
            <Route path="/" element={<LibraryPage/>}/>
            <Route path="/video/:id" element={<VideoEntry/>}/>
            <Route path="/video/:id/frame/:index" element={<StudioPage/>}/>
            <Route path="*" element={<Navigate to="/" replace={True}/>}/>
        </Routes>
    </Router>;
}
