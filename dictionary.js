const WordAheadDictionary = {
  shards:new Map(), pending:new Map(),
  install(id,entries) {this.shards.delete(id);this.shards.set(id,entries);while(this.shards.size>8)this.shards.delete(this.shards.keys().next().value);},
  nativeRequests:new Map(),
  receive(payload){const pending=this.nativeRequests.get(payload.id);if(!pending)return;this.nativeRequests.delete(payload.id);clearTimeout(pending.timer);payload.error?pending.reject(new Error(payload.error)):pending.resolve(payload.result);},
  native(action,extra={}){return new Promise((resolve,reject)=>{const id=crypto.randomUUID(),timer=setTimeout(()=>{this.nativeRequests.delete(id);reject(new Error('사전 응답이 지연됩니다. 다시 시도해주세요.'));},action==='download'?45*60*1000:action==='online'?15000:10000);this.nativeRequests.set(id,{resolve,reject,timer});try{window.webkit.messageHandlers.dictionaryStore.postMessage({id,action,...extra});}catch(error){clearTimeout(timer);this.nativeRequests.delete(id);reject(error);}});},
  async lookup(word) {
    if(window.webkit?.messageHandlers?.dictionaryStore){const result=await this.native('lookup',{word:word.toLowerCase()});return result.entry;}

    const key = word.toLowerCase();
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key)));
    const id = hash[0].toString(16).padStart(2,'0');
    if (!this.shards.has(id)) {
      if (!this.pending.has(id)) this.pending.set(id,new Promise((resolve,reject) => {
        const script=document.createElement('script');script.src=`dictionary/${id}.js?v=20261008`;
        script.onload=()=>{resolve(this.shards.get(id));this.pending.delete(id);script.remove();};
        script.onerror=()=>{this.pending.delete(id);script.remove();reject(new Error('내장 사전을 불러올 수 없습니다.'));};
        document.head.append(script);
      }));
      const entries=await this.pending.get(id);return entries&&Object.hasOwn(entries,key)?entries[key]:null;
    }
    const entries=this.shards.get(id);return Object.hasOwn(entries,key)?entries[key]:null;
  },
  async preferred(raw,key) {
    raw=raw.toLowerCase().replaceAll('’',"'");
    const exact=await this.lookup(raw);
    if(exact?.[3]==='ko'&&this.validMeaning(exact[2]))return {entry:exact,word:raw};
    const stems=[];if(/ies$/.test(raw))stems.push(raw.slice(0,-3)+'y');if(/ied$/.test(raw))stems.push(raw.slice(0,-3)+'y');if(/(?:ing|ed)$/.test(raw)){const stem=raw.replace(/(?:ing|ed)$/,'');stems.push(stem,stem+'e',stem.replace(/(.)\1$/,'$1'));}if(raw.endsWith('s')&&!raw.endsWith('ss'))stems.push(raw.slice(0,-1),raw.slice(0,-2));
    const forms=new Set([key,...stems,...Array.from((exact?.[2]||'').matchAll(/(?:plural|participle|tense|comparative|superlative|form)[^.;]*?\bof\s+([A-Za-z]+(?:['-][A-Za-z]+)*)/g),x=>x[1].toLowerCase())]);
    let fallback=null;
    for(const word of forms){if(word===raw)continue;const entry=await this.lookup(word);if(entry?.[3]==='ko'&&this.validMeaning(entry[2]))return {entry,word};if(entry&&!fallback)fallback={entry,word};}
    return exact?{entry:exact,word:raw}:fallback;
  },
  validMeaning(value){const text=String(value||'').replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();return /[가-힣]/.test(text)&&!/(?:뜻풀이를?\s*추가|이\s*틀|rfdety|한국어 뜻풀이가 필요|사전Name|번역을 추가|정의가 필요|뜻을 확인하는|불러오는 중|사전에서 뜻)/i.test(text);},
  readCache(){try{const value=JSON.parse(localStorage.getItem('wa-korean-meanings')||'{}');return value&&typeof value==='object'&&!Array.isArray(value)?value:{}}catch{return {}}},
  cached(word){const entry=this.readCache()[word];return entry&&this.validMeaning(entry[2])?{word,entry}:null;},
  remember(result){if(!result||!this.validMeaning(result.entry?.[2]))return result;const values=this.readCache();delete values[result.word];values[result.word]=[...result.entry];for(const key of Object.keys(values).slice(0,-1000))delete values[key];try{localStorage.setItem('wa-korean-meanings',JSON.stringify(values));}catch{}return result;},
  onlineCache:new Map(), inflight:new Map(),issues:new Map(),
  retry(raw,key){for(const word of [raw.toLowerCase(),key]){this.issues.delete(word);this.onlineCache.delete('ko:'+word);this.onlineCache.delete('translation-ko:'+word);}},
  failureMessage(raw,key){const issue=this.issues.get(raw.toLowerCase())||this.issues.get(key);return issue==='quota'?'번역 서비스 이용량 제한입니다. 오프라인 사전을 저장하거나 나중에 다시 조회해주세요.':issue==='network'?'온라인 사전이 응답하지 않습니다. 잠시 후 다시 조회해주세요.':'한글 뜻을 찾지 못했습니다. 다시 조회할 수 있어요.';},
  async json(url,signal){if(window.webkit?.messageHandlers?.dictionaryStore){const result=await this.native('online',{url});return JSON.parse(result.json);}const response=await fetch(url,{signal,credentials:'omit'});if(!response.ok)throw new Error('온라인 사전 응답 실패');return response.json();},
  async online(word,lang,signal) {
    const cacheKey=`${lang}:${word}`;
    if(this.onlineCache.has(cacheKey))return this.onlineCache.get(cacheKey);
    const params=new URLSearchParams({action:'parse',page:word,prop:'text',format:'json',origin:'*',redirects:'1',disableeditsection:'1',disablelimitreport:'1'});
    const data=await this.json(`https://${lang}.wiktionary.org/w/api.php?${params}`,signal);
    if(data.error){if(data.error.code==='missingtitle'){this.onlineCache.set(cacheKey,null);return null;}throw new Error(data.error.info);}
    const doc=new DOMParser().parseFromString(data.parse?.text?.['*']||'','text/html');
    let english=false,part='',phonetic='',definitions=[];
    for(const node of doc.querySelectorAll('h2,h3,h4,.IPA,ol > li')){
      if(node.tagName==='H2'){english=node.textContent.replace(/\[.*?\]/g,'').trim()===(lang==='ko'?'영어':'English');continue;}
      if(!english)continue;
      if(/^H[34]$/.test(node.tagName)){part=node.textContent.trim();continue;}
      if(node.classList.contains('IPA')){phonetic=phonetic||node.textContent.trim();continue;}
      if(node.closest('li li')||node.closest('.NavFrame,.quotations'))continue;
      const copy=node.cloneNode(true);copy.querySelectorAll('ul,ol,dl,sup,.HQToggle,.citation-whole').forEach(x=>x.remove());
      const text=copy.textContent.replace(/\s+/g,' ').trim();
      if(text&&definitions.length<3&&(lang!=='ko'||this.validMeaning(text)))definitions.push(text);
    }
    const result=definitions.length&&(lang!=='ko'||/[가-힣]/.test(definitions.join(' ')))?{word,entry:[phonetic,part,definitions.join('; '),lang],online:true}:null;
    this.onlineCache.set(cacheKey,result);while(this.onlineCache.size>200)this.onlineCache.delete(this.onlineCache.keys().next().value);
    return result;
  },
  async koreanTranslation(word,local){
    const cacheKey=`translation-ko:${word}`;if(this.onlineCache.has(cacheKey))return this.onlineCache.get(cacheKey);
    const definition=local?.entry?.[3]!=='ko'?String(local?.entry?.[2]||'').replace(/<[^>]*>/g,' ').split(';')[0].slice(0,300).trim():'';
    for(const query of [...new Set([word,...(definition&&definition!==word?[definition]:[])])]){
      const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);
      try{
        const params=new URLSearchParams({q:query,langpair:'en|ko'}),data=await this.json(`https://api.mymemory.translated.net/get?${params}`,controller.signal);
        if(Number(data.responseStatus)===429||data.quotaFinished){this.issues.set(word,'quota');break;}
        if(Number(data.responseStatus)!==200){this.issues.set(word,'network');continue;}
        const alternatives=(data.matches||[]).filter(x=>String(x.segment||'').toLowerCase()===query.toLowerCase()&&Number(x.match)>=.9).sort((a,b)=>Number(b.match)-Number(a.match));
        for(const candidate of [data.responseData?.translatedText,...alternatives.map(x=>x.translation)]){
          const meaning=new DOMParser().parseFromString(String(candidate||''),'text/html').body.textContent.trim();
          if(!this.validMeaning(meaning))continue;
          const result={word,entry:[local?.entry?.[0]||'',local?.entry?.[1]||'',meaning,'ko'],online:true,translated:true};
          this.onlineCache.set(cacheKey,result);this.issues.delete(word);while(this.onlineCache.size>200)this.onlineCache.delete(this.onlineCache.keys().next().value);return result;
        }
      }catch{this.issues.set(word,'network');}finally{clearTimeout(timer);}
    }
    return null;
  },
  async resolve(raw,key){const id=raw.toLowerCase()+'|'+key;if(this.inflight.has(id))return this.inflight.get(id);const task=this.resolveUncached(raw,key);this.inflight.set(id,task);try{return await task;}finally{this.inflight.delete(id);}},
  async resolveUncached(raw,key) {
    const cached=this.cached(raw.toLowerCase())||this.cached(key);if(cached)return cached;
    let local=null;try{local=await this.preferred(raw,key);}catch{}
    if(local?.entry[3]==='ko'&&!this.validMeaning(local.entry[2]))local=null;
    if(local?.entry[3]==='ko'||navigator.onLine===false)return local;
    const words=[...new Set([raw.toLowerCase().replaceAll('’',"'"),local?.word,key].filter(Boolean))];
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),5000);
    try{
      for(const word of words){
        if(controller.signal.aborted)break;
        try{const result=await this.online(word,'ko',controller.signal);if(result){result.entry[0]=result.entry[0]||local?.entry[0]||'';return this.remember(result);}}catch{}
      }
    }finally{clearTimeout(timer);}
    const translated=await this.koreanTranslation(local?.word||words[0],local);
    return translated?this.remember(translated):local;
  },
  async show(raw,key) {
    const selection=currentWord;
    try {
      const result=await this.resolve(raw,key);
      if(currentWord!==selection)return;
      if(!result){if(!this.validMeaning(selection.entry?.[2]))$('#sheet-meaning').textContent=this.failureMessage(raw,key);return;}
      const word=result.word,entry=[...result.entry];entry[2]=plainDictionaryMeaning(entry[2]);
      if(entry[3]!=='ko'&&this.validMeaning(selection.entry?.[2]))return;
      selection.entry=entry;
      $('#sheet-part').textContent=entry[1];$('#sheet-phonetic').textContent=entry[0]||'';
      $('#sheet-meaning').textContent=entry[3]==='ko'?entry[2]:this.failureMessage(raw,key)+`\n참고 영문: ${entry[2]}`;

      const existing=saved.find(x=>x.word===key);
      if(existing&&entry[3]==='ko'){existing.definition=entry[2];existing.phonetic=entry[0];existing.part=entry[1];persist();}
    }catch{if(currentWord===selection&&!this.validMeaning(selection.entry?.[2]))$('#sheet-meaning').textContent=this.failureMessage(raw,key);}
    finally{if(currentWord===selection)$('#sheet-retry').hidden=this.validMeaning(selection.entry?.[2]);}
  }
};

async function refreshOfflineDictionary(){
 const button=document.querySelector('#download-dictionary'),status=document.querySelector('#dictionary-status');
 if(!button)return;
 if(!window.webkit?.messageHandlers?.dictionaryStore){button.hidden=true;status.textContent='확장 사전 다운로드는 iPhone 앱에서 지원합니다.';return;}
 try{const state=await WordAheadDictionary.native('status');button.disabled=state.complete;button.textContent=state.complete?'확장 사전 최신 상태':'확장 사전 다운로드 · Wi-Fi';status.textContent=state.complete?'확장 사전 저장 완료 · 앱 업데이트 후에도 유지됩니다.':`기본 영한 사전 사용 중 · 확장 사전 ${state.downloaded}/${state.total}개 저장됨 (전체 약 ${Math.ceil(state.bytes/1000000)}MB)`;}catch{status.textContent='사전 상태를 확인하지 못했습니다.';}
}
async function downloadOfflineDictionary(){
 const button=document.querySelector('#download-dictionary'),status=document.querySelector('#dictionary-status');
 button.disabled=true;status.textContent='Wi-Fi로 다운로드 중입니다. 앱을 열어두세요. 중단되면 다음에 이어받습니다.';
 try{const result=await WordAheadDictionary.native('download');await refreshOfflineDictionary();if(result.busy)status.textContent='사전을 이미 저장 중입니다. 잠시 후 다시 확인해주세요.';return result.complete===true;}catch(error){button.disabled=false;status.textContent=error.message;return false;}
}
document.querySelector('#download-dictionary')?.addEventListener('click',downloadOfflineDictionary);
async function offerOfflineDictionary(){
 const dialog=document.querySelector('#offline-offer');if(!dialog||!window.webkit?.messageHandlers?.dictionaryStore||localStorage.getItem('wa-offline-offer')||document.querySelector('dialog[open]'))return;
 try{const state=await WordAheadDictionary.native('status');if(state.complete){localStorage.setItem('wa-offline-offer','complete');return;}
 document.querySelector('#offline-offer-description').textContent=`Wi-Fi에서 확장 영한 사전 약 ${Math.ceil(state.bytes/1000000)}MB를 저장할까요? 인터넷 없이 더 많은 단어 뜻을 볼 수 있고 앱 업데이트 후에도 유지됩니다. 나중에 환경설정에서도 저장할 수 있습니다.`;
 if(localStorage.getItem('wa-offline-offer')||document.querySelector('dialog[open]'))return;dialog.showModal();localStorage.setItem('wa-offline-offer','asked');}catch{}
}
document.querySelector('#offline-later')?.addEventListener('click',()=>document.querySelector('#offline-offer').close());
document.querySelector('#offline-save')?.addEventListener('click',async()=>{
 const button=document.querySelector('#offline-save'),status=document.querySelector('#offline-offer-status');button.disabled=true;document.querySelector('#offline-later').textContent='닫기';status.textContent='Wi-Fi로 저장 중입니다. 앱을 열어두세요.';
 const complete=await downloadOfflineDictionary();status.textContent=complete?'오프라인 사전을 저장했습니다.':document.querySelector('#dictionary-status').textContent;button.disabled=complete;button.textContent=complete?'저장 완료':'다시 저장';if(complete){localStorage.setItem('wa-offline-offer','complete');const dialog=document.querySelector('#offline-offer');if(dialog.open)dialog.close();}
});
refreshOfflineDictionary();
document.addEventListener('DOMContentLoaded',offerOfflineDictionary,{once:true});
document.querySelectorAll('dialog').forEach(dialog=>dialog.addEventListener('close',offerOfflineDictionary));
