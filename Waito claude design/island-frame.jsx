/**
 * Waito Dynamic Island Frame — v3
 *
 * 핵심:
 *  - 외곽 silhouette 은 그대로(까만 알약 합체) 그리고,
 *  - "안쪽 테두리" = silhouette 에서 INSET 만큼 안으로 들어온 path 위에 그리는
 *    회색 트랙 + 오렌지 진행 stroke.
 *  - 진행 시작점 = 카메라 좌측 fillet 시작, 끝점 = 카메라 우측 fillet 끝.
 *  - 트럭은 진행/회색 경계점 위쪽(법선 바깥쪽)으로 살짝 떠 있음.
 */

const ISLAND_W = 372;
const ISLAND_H = 240;
const CAM_W = 122;
const CAM_H = 36;
const SIDE_R = 44;
const STROKE = 5;
const INSET = 9;     // 안쪽 테두리 — silhouette 으로부터 안으로 들어온 거리 (시각적으로 명확히 안쪽)

// 외곽 path 빌더 — inset 으로 안쪽 path 도 같은 함수에서 만듦
function buildIslandPath(insetVal = 0) {
  const W = ISLAND_W, H = ISLAND_H;
  const r = Math.max(0, SIDE_R - insetVal);
  const cw = CAM_W, ch = CAM_H;
  const cx0 = (W - cw) / 2;
  const cx1 = (W + cw) / 2;
  const fillet = ch + insetVal;
  const left = insetVal;
  const right = W - insetVal;
  const top = insetVal;
  const bot = H - insetVal;
  const camBotY = ch + insetVal;

  return [
    `M ${cx0} ${camBotY}`,
    `A ${fillet} ${fillet} 0 0 1 ${cx0 - fillet} ${top}`,
    `L ${r + left} ${top}`,
    `A ${r} ${r} 0 0 1 ${left} ${top + r}`,
    `L ${left} ${bot - r}`,
    `A ${r} ${r} 0 0 1 ${left + r} ${bot}`,
    `L ${right - r} ${bot}`,
    `A ${r} ${r} 0 0 1 ${right} ${bot - r}`,
    `L ${right} ${top + r}`,
    `A ${r} ${r} 0 0 1 ${right - r} ${top}`,
    `L ${cx1 + fillet} ${top}`,
    `A ${fillet} ${fillet} 0 0 1 ${cx1} ${camBotY}`,
  ].join(' ');
}

const ISLAND_OUTLINE_D = buildIslandPath(0);
const ISLAND_PROGRESS_D = buildIslandPath(INSET);

// silhouette 채움용 (닫힌 path)
const ISLAND_FILL_D = ISLAND_OUTLINE_D + ` L ${(ISLAND_W - CAM_W) / 2} ${CAM_H} Z`;

// 카메라 알약
const CAMERA_PILL_D = (() => {
  const W = ISLAND_W, ch = CAM_H, cw = CAM_W;
  const cr = ch / 2;
  const cx0 = (W - cw) / 2;
  const cx1 = (W + cw) / 2;
  return [
    `M ${cx0} ${ch}`,
    `A ${cr} ${cr} 0 0 1 ${cx0} 0`,
    `L ${cx1} 0`,
    `A ${cr} ${cr} 0 0 1 ${cx1} ${ch}`,
    `Z`,
  ].join(' ');
})();

// 안쪽 컨텐츠 클립 (silhouette 와 같음 — 카메라 부분 제외)
const CONTENT_CLIP_D = ISLAND_FILL_D;

// --- 컴포넌트 ---------------------------------------------------------------
function IslandFrame({
  progress = 0.62,
  showTruck = true,
  innerContent = null,
  bg = "#000",
  trackColor = "rgba(255,255,255,0.16)",
  fillColor = "#FF7A1A",
  scale = 1,
}) {
  const pathRef = React.useRef(null);
  const [pathLen, setPathLen] = React.useState(1200);
  const [truckPos, setTruckPos] = React.useState({ x: 0, y: 0, angle: 0 });

  React.useEffect(() => {
    if (!pathRef.current) return;
    const len = pathRef.current.getTotalLength();
    setPathLen(len);
    const at = Math.max(0.0001, Math.min(0.9999, progress));
    const p = pathRef.current.getPointAtLength(len * at);
    const p2 = pathRef.current.getPointAtLength(Math.min(len, len * at + 1));
    const ang = (Math.atan2(p2.y - p.y, p2.x - p.x) * 180) / Math.PI;
    setTruckPos({ x: p.x, y: p.y, angle: ang });
  }, [progress]);

  const W = ISLAND_W, H = ISLAND_H;
  const PAD = 18;

  return (
    <div style={{ width: W * scale, height: H * scale, position: 'relative' }}>
      <svg
        width={(W + PAD * 2) * scale}
        height={(H + PAD * 2) * scale}
        viewBox={`${-PAD} ${-PAD} ${W + PAD * 2} ${H + PAD * 2}`}
        style={{
          display: 'block',
          position: 'absolute',
          left: -PAD * scale,
          top: -PAD * scale,
          overflow: 'visible',
        }}
      >
        <defs>
          <clipPath id="island-content-clip">
            <path d={CONTENT_CLIP_D} />
          </clipPath>
        </defs>

        {/* 본체 검정 silhouette */}
        <path d={ISLAND_FILL_D} fill={bg} />
        <path d={CAMERA_PILL_D} fill={bg} />

        {/* 안쪽 컨텐츠 */}
        <foreignObject
          x="0" y={CAM_H}
          width={W} height={H - CAM_H}
          clipPath="url(#island-content-clip)"
        >
          <div xmlns="http://www.w3.org/1999/xhtml" style={{ width: '100%', height: '100%', color: 'white' }}>
            {innerContent}
          </div>
        </foreignObject>

        {/* 안쪽 테두리: 회색 트랙 (전체) */}
        <path
          ref={pathRef}
          d={ISLAND_PROGRESS_D}
          fill="none"
          stroke={trackColor}
          strokeWidth={STROKE}
          strokeLinecap="round"
        />

        {/* 안쪽 테두리: 오렌지 진행 부분 */}
        <path
          d={ISLAND_PROGRESS_D}
          fill="none"
          stroke={fillColor}
          strokeWidth={STROKE}
          strokeLinecap="round"
          strokeDasharray={`${pathLen * progress} ${pathLen}`}
          style={{ transition: 'stroke-dasharray 0.5s cubic-bezier(.4,0,.2,1)' }}
        />

        {/* 픽셀 트럭 — 진행/회색 경계점 위(법선 안쪽 = 카메라 쪽) */}
        {showTruck && progress > 0.005 && progress < 0.995 && (
          <g
            transform={`translate(${truckPos.x}, ${truckPos.y})`}
            style={{ transition: 'transform 0.5s cubic-bezier(.4,0,.2,1)' }}
          >
            <PixelTruck angle={truckPos.angle} />
          </g>
        )}
      </svg>
    </div>
  );
}

// --- 픽셀 트럭 ---------------------------------------------------------------
function PixelTruck({ angle = 0 }) {
  // 진행 방향의 "안쪽 법선" = 다이나믹 아일랜드 중심 쪽으로 트럭이 위치.
  // path 가 시계 반대로 도는 닫힌 형태이므로, 안쪽 법선은 진행방향의 왼쪽(=시계 방향 90도).
  const rad = (angle * Math.PI) / 180;
  // 진행방향의 왼쪽 단위벡터 (-sin(angle-90), cos(angle-90)) 등가:
  const lx =  Math.sin(rad);   // 안쪽으로
  const ly = -Math.cos(rad);
  const off = 10;
  const ox = lx * off;
  const oy = ly * off;
  // 트럭의 "위쪽"은 안쪽 방향의 반대 = 바깥쪽(silhouette 방향)
  const upAngle = Math.atan2(-ly, -lx) * 180 / Math.PI - 90;

  const px = 1.6;
  const grid = [
    "..OOOO..",
    "OO....OO",
    "OCCCCCCO",
    "OCCCCCCO",
    ".CWCCWC.",
  ];
  const cellsW = 8;
  const cellsH = grid.length;
  const Wt = cellsW * px;
  const Ht = cellsH * px;

  return (
    <g transform={`translate(${ox}, ${oy}) rotate(${upAngle}) translate(${-Wt / 2}, ${-Ht / 2})`}>
      <ellipse cx={Wt / 2} cy={Ht + 1.2} rx={Wt / 2.4} ry={1.0} fill="rgba(0,0,0,0.55)" />
      {grid.map((row, y) =>
        row.split('').map((c, x) => {
          if (c === '.') return null;
          let fill = '#FFFFFF';
          if (c === 'O') fill = '#FFB070';
          if (c === 'C') fill = '#FFFFFF';
          if (c === 'W') fill = '#1A1A1A';
          return (
            <rect
              key={`${x}-${y}`}
              x={x * px} y={y * px}
              width={px + 0.4} height={px + 0.4}
              fill={fill}
              shapeRendering="crispEdges"
            />
          );
        })
      )}
      <rect x={cellsW * px - px - 0.2} y={2 * px} width={px} height={px} fill="#FFE08A" shapeRendering="crispEdges" />
    </g>
  );
}

window.IslandFrame = IslandFrame;
window.PixelTruck = PixelTruck;
window.ISLAND_W = ISLAND_W;
window.ISLAND_H = ISLAND_H;
window.CAM_H = CAM_H;
