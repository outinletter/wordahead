const origins = new Set(['https://outinletter.github.io', 'http://localhost:8978', 'http://127.0.0.1:8978', 'null']);
const json = (body, status, origin) => new Response(JSON.stringify(body), {status, headers: {'Content-Type':'application/json; charset=utf-8', 'Access-Control-Allow-Origin':origin, 'Vary':'Origin', 'Cache-Control':'no-store'}});
async function youtube(url, options = {}) {
  const response = await fetch(url, {...options, signal:AbortSignal.timeout(15000)});
  if (!response.ok) throw new Error('YouTube에서 자막 요청을 거절했습니다. 잠시 후 다시 시도하세요.');
  return response;
}
export async function captions(videoId) {
  if (!/^[\w-]{11}$/.test(videoId || '')) throw new Error('올바른 YouTube 영상 주소를 입력하세요.');
  const html = await (await youtube(`https://www.youtube.com/watch?v=${videoId}`)).text();
  const key = html.match(/"INNERTUBE_API_KEY":\s*"([\w-]+)"/)?.[1];
  if (!key) throw new Error('YouTube에서 이 영상의 자막 접근을 허용하지 않았습니다.');
  const player = await (await youtube(`https://www.youtube.com/youtubei/v1/player?key=${key}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({context:{client:{clientName:'ANDROID',clientVersion:'20.10.38'}},videoId})})).json();
  if (player.playabilityStatus?.status !== 'OK') throw new Error('비공개·연령 제한 영상 또는 현재 접근할 수 없는 영상입니다.');
  const tracks = player.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
  const track = tracks.find(t => /^en(?:-|$)/.test(t.languageCode) && t.kind === 'asr') || tracks.find(t => /^en(?:-|$)/.test(t.languageCode));
  if (!track) throw new Error('이 영상에는 수집 가능한 영어 자막이 없습니다.');
  const url = new URL(track.baseUrl);
  if (url.protocol !== 'https:' || !['www.youtube.com','youtube.com'].includes(url.hostname) || url.searchParams.get('exp') === 'xpe') throw new Error('YouTube에서 추가 인증을 요구해 자동 수집할 수 없습니다.');
  url.searchParams.set('fmt','json3');
  const raw = await (await youtube(url.href)).text();
  if (!raw.trim()) throw new Error('YouTube가 자막 본문을 제공하지 않았습니다.');
  const data = JSON.parse(raw);
  const segments = (data.events || []).filter(e => e.segs).map(e => ({start:Number(e.tStartMs || 0)/1000,text:e.segs.map(s => s.utf8 || '').join('').replace(/\s+/g,' ').trim()})).filter(e => e.text);
  if (!segments.length) throw new Error('영어 자막 본문이 비어 있습니다.');
  return {videoId,title:player.videoDetails?.title || 'YouTube 영어 자막',channel:player.videoDetails?.author || 'YouTube',language:track.languageCode,isGenerated:track.kind === 'asr',segments};
}
export default {async fetch(request) {
  const origin = request.headers.get('Origin') || 'null';
  if (!origins.has(origin)) return json({error:'허용되지 않은 요청입니다.'},403,'null');
  if (request.method === 'OPTIONS') return new Response(null,{status:204,headers:{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'GET, OPTIONS','Vary':'Origin'}});
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.pathname !== '/api/captions') return json({error:'Not found'},404,origin);
  try {return json(await captions(url.searchParams.get('videoId')),200,origin);} catch (error) {return json({error:error.message || '자막 수집에 실패했습니다.'},422,origin);}
}};
