const WordAheadCaptions = {
  requests: new Map(),
  async open(video) {
    activeVideo=video;setView('reader');
    $('#reader-title').textContent=video.title;
    $('#transcript-content').innerHTML='<p class="empty-state" role="status">영어 자막을 수집하고 있어요…</p>';
    try {
      const data=await this.fetch(video.youtubeId);
      if(activeVideo!==video||$('#reader-view').hidden)return;
      video.text=data.segments.map(x=>x.text).join('\n');video.segments=data.segments;
      video.title=data.title;video.channel=data.channel;video.caption=true;
      video.meta=data.isGenerated?'영어(자동) 자막':'영어 자막';
      persist();renderCards();openReader(video);
    } catch(error) {
      if(activeVideo!==video||$('#reader-view').hidden)return;
      $('#transcript-content').innerHTML=`<div class="empty-state"><p>${escapeHtml(error.message)}</p><button class="primary-button" data-action="read" data-id="${escapeHtml(video.id)}">다시 시도</button><button class="text-button" id="manual-caption">자막 직접 입력</button></div>`;
      $('#manual-caption').onclick=()=>openCaptionDialog(video);
    }
  },
  async fetch(videoId) {
    if (window.webkit?.messageHandlers?.captions) {
      return new Promise((resolve,reject) => {
        const id = crypto.randomUUID();
        const timer = setTimeout(() => {this.requests.delete(id);reject(new Error('자막 수집 시간이 초과됐습니다. 다시 시도하세요.'));},45000);
        this.requests.set(id,{resolve,reject,timer});
        window.webkit.messageHandlers.captions.postMessage({id,videoId});
      });
    }
    const endpoint = document.querySelector('meta[name="caption-api"]')?.content;
    if (!endpoint) throw new Error('자막 서버 연결이 설정되지 않았습니다.');
    const response = await fetch(`${endpoint}?videoId=${encodeURIComponent(videoId)}`,{signal:AbortSignal.timeout(45000)});
    const data = await response.json();
    if (!response.ok || data.error) throw new Error(data.error || '영어 자막을 수집할 수 없습니다.');
    return data;
  },
  complete(id,data,error) {
    const pending = this.requests.get(id);
    if (!pending) return;
    clearTimeout(pending.timer);this.requests.delete(id);
    if (error) pending.reject(new Error(error));else pending.resolve(data);
  }
};
