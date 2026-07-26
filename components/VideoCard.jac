"""One ingested video in the library, as a link into its studio."""

import from "@jac/runtime" { Link }
import from .MetaChip { MetaChip }
import from .overlay_geometry { clock }

sv import from ..library { VideoView }

def:pub VideoCard(video: VideoView) -> JsxElement {
    redaction_tone = "danger" if video.box_count > 0 else "muted";
    return <Link to={"/video/" + video.id} className="vcard">
        <div className="vcard-shot">
            {if video.poster_url {
                <img className="vcard-img" src={video.poster_url} alt="" loading="lazy"/>
            } else {
                <div className="vcard-img vcard-img-empty"/>
            }}
            <span className="vcard-dur">{clock(video.duration)}</span>
            {if video.export_url {
                <span className="vcard-flag">exported</span>
            }}
        </div>
        <div className="vcard-body">
            <h3 className="vcard-title">{video.title}</h3>
            <p className="vcard-path">
                {str(video.width) + "x" + str(video.height)}
                {" · "}
                {f"{video.source_fps:.0f} fps source"}
                {" · "}
                <span className="vcard-hash">{video.video_hash}</span>
            </p>
            <div className="vcard-chips">
                <MetaChip label="frames" value={str(video.frame_count)}/>
                <MetaChip label="ocr" value={str(video.ocr_frame_count) + "/" + str(video.frame_count)}/>
                <MetaChip label="words" value={str(video.word_count)}/>
                <MetaChip label="boxes" value={str(video.box_count)} tone={redaction_tone}/>
            </div>
        </div>
    </Link>;
}
