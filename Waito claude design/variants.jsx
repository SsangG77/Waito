/**
 * Waito 다이나믹 아일랜드 — 안쪽 컨텐츠 베리에이션 4종
 *
 * 모두 SwiftUI 의 expanded Live Activity region 에서 구현 가능한 수준으로
 * 단순한 HStack/VStack/Text/Image 조합으로만 만듭니다.
 *
 * 공통 스펙:
 *   - 영역: width 372, height 약 198 (전체 240 - 카메라 영역 42)
 *   - 색상: 배경은 검정(테두리 path 가 그려줌), 텍스트는 흰색 베이스
 *   - 오렌지 강조: #FF7A1A
 */

const STAGES = [
  { key: 'received',  label: '주문 접수',     pct: 0.08, icon: '📋', sub: '주문이 확인됐어요' },
  { key: 'preparing', label: '상품 준비중',    pct: 0.22, icon: '📦', sub: '판매자가 포장 중' },
  { key: 'picked',    label: '집화 완료',     pct: 0.40, icon: '🚚', sub: '택배 기사님이 픽업했어요' },
  { key: 'in_transit',label: '배송 중',       pct: 0.62, icon: '🛣️', sub: '허브 터미널 출발' },
  { key: 'out',       label: '배송 출발',     pct: 0.85, icon: '📍', sub: '오늘 도착 예정' },
  { key: 'delivered', label: '배송 완료',     pct: 1.00, icon: '✅', sub: '문 앞에 두고 갔어요' },
];

function stageFromProgress(p) {
  let s = STAGES[0];
  for (const stage of STAGES) {
    if (p >= stage.pct - 0.001) s = stage;
  }
  return s;
}

// ============================================================================
// Variation A — "정보 밀도형": 상품 + 단계 + ETA + CTA
// 가장 일반적이고 안전한 레이아웃
// ============================================================================
function VariantA({ progress, stage }) {
  return (
    <div style={{
      width: '100%', height: '100%',
      padding: '14px 28px 18px 28px',
      display: 'flex', flexDirection: 'column', gap: 10,
      fontFamily: 'system-ui, -apple-system, "SF Pro Text", sans-serif',
      color: 'white',
      boxSizing: 'border-box',
    }}>
      <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
        {/* 상품 썸네일 */}
        <div style={{
          width: 44, height: 44, borderRadius: 10,
          background: 'linear-gradient(135deg, #2a2a2e, #1a1a1e)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 22, flexShrink: 0,
          boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.06)',
        }}>👟</div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontSize: 11, fontWeight: 600, color: '#FF7A1A',
            letterSpacing: 0.3, textTransform: 'uppercase',
          }}>
            {stage.label}
          </div>
          <div style={{
            fontSize: 14, fontWeight: 600, marginTop: 2,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>
            나이키 에어포스 1 '07
          </div>
        </div>
      </div>

      {/* 분리선 */}
      <div style={{ height: 1, background: 'rgba(255,255,255,0.08)' }} />

      {/* ETA + 택배사 */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <div>
          <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)', marginBottom: 2 }}>예상 도착</div>
          <div style={{ fontSize: 18, fontWeight: 700, lineHeight: 1 }}>
            오늘 오후 <span style={{ color: '#FF7A1A' }}>3:40</span>
          </div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)', marginBottom: 2 }}>CJ대한통운</div>
          <div style={{ fontSize: 11, fontFamily: 'ui-monospace, monospace', color: 'rgba(255,255,255,0.85)' }}>
            6182··3490
          </div>
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Variation B — "타임라인형": 단계별 마일스톤 점
// 진행 흐름을 안에서 한 번 더 시각화. 도트가 단계별로 채워짐.
// ============================================================================
function VariantB({ progress, stage }) {
  const milestones = ['접수', '준비', '집화', '배송', '출발', '도착'];
  const milestonePcts = [0.0, 0.22, 0.40, 0.62, 0.85, 1.0];
  const activeIdx = milestonePcts.findIndex((p, i) =>
    progress < (milestonePcts[i + 1] ?? 1.01)
  );

  return (
    <div style={{
      width: '100%', height: '100%',
      padding: '14px 26px 16px 26px',
      display: 'flex', flexDirection: 'column', gap: 12,
      fontFamily: 'system-ui, -apple-system, "SF Pro Text", sans-serif',
      color: 'white',
      boxSizing: 'border-box',
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div>
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: -0.4 }}>
            {stage.label}
          </div>
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.55)', marginTop: 2 }}>
            {stage.sub}
          </div>
        </div>
        <div style={{
          fontSize: 13, fontWeight: 700, color: '#FF7A1A',
          fontFeatureSettings: '"tnum"',
        }}>
          {Math.round(progress * 100)}%
        </div>
      </div>

      {/* 픽셀 지하철 노선 트랙 — 사각 도트 + 짧은 선분 */}
      <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{
          display: 'flex', alignItems: 'center', width: '100%',
          imageRendering: 'pixelated',
        }}>
          {milestones.map((m, i) => {
            const isDone = i < activeIdx;
            const isActive = i === activeIdx;
            const isLast = i === milestones.length - 1;
            const dotColor = (isDone || isActive) ? '#FF7A1A' : '#2C3A55';
            const lineColor = isDone ? '#FF7A1A' : '#2C3A55';
            return (
              <React.Fragment key={m}>
                <div style={{
                  width: 7, height: 7,
                  background: dotColor,
                  flexShrink: 0,
                  shapeRendering: 'crispEdges',
                  boxShadow: isActive ? '0 0 4px rgba(255,122,26,0.7)' : 'none',
                }} />
                {!isLast && (
                  <div style={{
                    flex: 1, height: 2,
                    background: lineColor,
                    margin: '0 3px',
                    transition: 'background 0.4s',
                  }} />
                )}
              </React.Fragment>
            );
          })}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
          {milestones.map((m, i) => (
            <div key={m} style={{
              fontSize: 9.5,
              color: i <= activeIdx ? 'rgba(255,255,255,0.85)' : 'rgba(255,255,255,0.35)',
              fontWeight: i === activeIdx ? 700 : 500,
              fontFamily: 'ui-monospace, "SF Mono", monospace',
            }}>{m}</div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Variation C — "거대 타이포형": ETA 를 압도적으로 크게
// 배달 앱의 "30분" 타이포처럼 시간 자체가 주인공
// ============================================================================
function VariantC({ progress, stage }) {
  // 진행률에 따른 가상의 ETA 계산
  const minutesLeft = Math.max(0, Math.round((1 - progress) * 180));
  const hoursLeft = Math.floor(minutesLeft / 60);
  const minsRest = minutesLeft % 60;

  return (
    <div style={{
      width: '100%', height: '100%',
      padding: '12px 28px 16px 28px',
      display: 'flex', flexDirection: 'column',
      fontFamily: 'system-ui, -apple-system, "SF Pro Display", sans-serif',
      color: 'white',
      boxSizing: 'border-box',
      position: 'relative',
    }}>
      <div style={{
        fontSize: 10, fontWeight: 700, letterSpacing: 1.4,
        color: '#FF7A1A', textTransform: 'uppercase',
      }}>
        {stage.label}
      </div>

      <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 4 }}>
        {progress >= 1 ? (
          <div style={{ fontSize: 56, fontWeight: 800, letterSpacing: -3, lineHeight: 1 }}>
            도착
          </div>
        ) : (
          <>
            <div style={{
              fontSize: 64, fontWeight: 800, letterSpacing: -3.5, lineHeight: 0.9,
              fontFeatureSettings: '"tnum"',
              background: 'linear-gradient(180deg, #fff 0%, #fff 60%, #d8d8d8 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
            }}>
              {hoursLeft > 0 ? hoursLeft : minutesLeft}
            </div>
            <div style={{ fontSize: 22, fontWeight: 600, color: 'rgba(255,255,255,0.7)' }}>
              {hoursLeft > 0 ? `시 ${minsRest}분` : '분'}
            </div>
            <div style={{
              fontSize: 13, fontWeight: 500, color: 'rgba(255,255,255,0.45)',
              marginLeft: 'auto', alignSelf: 'flex-end', paddingBottom: 6,
            }}>
              남음
            </div>
          </>
        )}
      </div>

      <div style={{
        marginTop: 'auto',
        display: 'flex', alignItems: 'center', gap: 8,
        fontSize: 12, color: 'rgba(255,255,255,0.55)',
      }}>
        <div style={{ width: 4, height: 4, borderRadius: 2, background: '#FF7A1A' }} />
        나이키 에어포스 1 · CJ대한통운
      </div>
    </div>
  );
}

// ============================================================================
// Variation D — "지도 미니뷰형": 추상 지도 + 트럭 위치 핀
// SwiftUI 에서는 Canvas 또는 Path 로 구현 (실제 MapKit 은 Live Activity 제약상 어려움)
// ============================================================================
function VariantD({ progress, stage }) {
  return (
    <div style={{
      width: '100%', height: '100%',
      padding: '12px 24px 14px 24px',
      display: 'flex', flexDirection: 'column', gap: 10,
      fontFamily: 'system-ui, -apple-system, "SF Pro Text", sans-serif',
      color: 'white',
      boxSizing: 'border-box',
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <div style={{ fontSize: 13, fontWeight: 700 }}>{stage.label}</div>
          <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)', marginTop: 1 }}>
            {stage.sub}
          </div>
        </div>
        <div style={{
          padding: '3px 8px',
          borderRadius: 8,
          background: 'rgba(255,122,26,0.18)',
          fontSize: 10, fontWeight: 700, color: '#FFB070',
          fontFeatureSettings: '"tnum"',
        }}>
          ETA 3:40 PM
        </div>
      </div>

      {/* 추상 지도 */}
      <div style={{
        flex: 1,
        position: 'relative',
        borderRadius: 12,
        background: 'linear-gradient(135deg, #15171a 0%, #0d0e10 100%)',
        overflow: 'hidden',
        boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.04)',
      }}>
        <svg width="100%" height="100%" viewBox="0 0 320 90" preserveAspectRatio="xMidYMid slice">
          {/* 그리드 */}
          {[...Array(8)].map((_, i) => (
            <line key={`v${i}`} x1={i * 40} y1="0" x2={i * 40} y2="90" stroke="rgba(255,255,255,0.04)" />
          ))}
          {[...Array(3)].map((_, i) => (
            <line key={`h${i}`} x1="0" y1={i * 30 + 15} x2="320" y2={i * 30 + 15} stroke="rgba(255,255,255,0.04)" />
          ))}
          {/* 도로 (시작점 → 끝점) */}
          <path d="M 30 70 Q 90 70, 130 50 T 230 30 T 290 25"
                fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth="3" strokeLinecap="round" />
          <path d="M 30 70 Q 90 70, 130 50 T 230 30 T 290 25"
                fill="none" stroke="#FF7A1A" strokeWidth="3" strokeLinecap="round"
                strokeDasharray="500"
                strokeDashoffset={500 - 500 * progress}
                style={{ transition: 'stroke-dashoffset 0.5s ease' }} />
          {/* 출발점 */}
          <circle cx="30" cy="70" r="4" fill="#3a3a3e" stroke="white" strokeWidth="1.5" />
          {/* 도착점 (집) */}
          <g transform="translate(290, 25)">
            <circle r="7" fill="#FF7A1A" />
            <text y="3" textAnchor="middle" fontSize="9" fill="white">🏠</text>
          </g>
          {/* 트럭 위치 (간단한 점) */}
          {(() => {
            // 도로 path 의 progress 위치를 근사 (직선보간)
            const points = [[30,70],[130,50],[230,30],[290,25]];
            const segs = points.length - 1;
            const t = progress * segs;
            const i = Math.min(segs - 1, Math.floor(t));
            const f = t - i;
            const x = points[i][0] + (points[i+1][0] - points[i][0]) * f;
            const y = points[i][1] + (points[i+1][1] - points[i][1]) * f;
            return (
              <g transform={`translate(${x}, ${y})`}>
                <circle r="6" fill="#FF7A1A" opacity="0.3" />
                <circle r="3" fill="#FFB070" />
              </g>
            );
          })()}
        </svg>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: 'rgba(255,255,255,0.45)' }}>
        <span>옥천 HUB</span>
        <span style={{ color: 'rgba(255,255,255,0.7)' }}>{Math.round(progress * 100)}% 이동</span>
        <span>우리집</span>
      </div>
    </div>
  );
}

window.STAGES = STAGES;
window.stageFromProgress = stageFromProgress;
window.VariantA = VariantA;
window.VariantB = VariantB;
window.VariantC = VariantC;
window.VariantD = VariantD;
