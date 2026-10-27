const WordAheadDictionary = {
  shards:new Map(), pending:new Map(),
  install(id,entries) {this.shards.delete(id);this.shards.set(id,entries);while(this.shards.size>8)this.shards.delete(this.shards.keys().next().value);},
  nativeRequests:new Map(),
  receive(payload){const pending=this.nativeRequests.get(payload.id);if(!pending)return;this.nativeRequests.delete(payload.id);clearTimeout(pending.timer);payload.error?pending.reject(new Error(payload.error)):pending.resolve(payload.result);},
  native(action,extra={}){return new Promise((resolve,reject)=>{const id=crypto.randomUUID(),timer=setTimeout(()=>{this.nativeRequests.delete(id);reject(new Error('사전 응답이 지연됩니다. 다시 시도해주세요.'));},action==='download'?45*60*1000:action==='online'?15000:10000);this.nativeRequests.set(id,{resolve,reject,timer});try{window.webkit.messageHandlers.dictionaryStore.postMessage({id,action,...extra});}catch(error){clearTimeout(timer);this.nativeRequests.delete(id);reject(error);}});},
  localEntries:new Map(),
  async prefetch(words){
    if(!window.webkit?.messageHandlers?.dictionaryStore){await this.loadBundled();return;}
    const keys=[...new Set(words.flatMap(w=>[w.raw.toLowerCase(),w.word]))];
    const result=await this.native('lookupMany',{words:JSON.stringify(keys)});
    this.localEntries=new Map(Object.entries(result.entries||{}));
  },
  bundled:null,
  async loadBundled(){
    if(!this.bundled)this.bundled=Promise.all(['kengdic-ko.json','core-ko.json'].map(async name=>{
      const response=await fetch(`dictionary/${name}?v=korean-20261027`,{signal:AbortSignal.timeout(10000)});
      if(!response.ok)throw new Error('내장 영한 사전을 불러올 수 없습니다.');return response.json();
    })).then(([supplement,core])=>({...supplement,...core})).catch(error=>{this.bundled=null;throw error;});
    return this.bundled;
  },
  async lookup(word) {
    const key=word.toLowerCase();
    if(this.localEntries.has(key))return this.localEntries.get(key);
    if(window.webkit?.messageHandlers?.dictionaryStore){const result=await this.native('lookup',{word:key});return result.entry;}
    const entries=await this.loadBundled();return Object.hasOwn(entries,key)?entries[key]:null;
  },
  async preferred(raw,key) {
    raw=raw.toLowerCase().replaceAll('’',"'");
    const cached=this.cached(raw)||this.cached(key);if(cached)return cached;
    const exact=await this.lookup(raw);
    if(exact?.[3]==='ko'&&this.validMeaning(exact[2]))return this.remember({entry:exact,word:raw});
    const stems=[];if(/ies$/.test(raw))stems.push(raw.slice(0,-3)+'y');if(/ied$/.test(raw))stems.push(raw.slice(0,-3)+'y');if(/(?:ing|ed)$/.test(raw)){const stem=raw.replace(/(?:ing|ed)$/,'');stems.push(stem,stem+'e',stem.replace(/(.)\1$/,'$1'));}if(raw.endsWith('s')&&!raw.endsWith('ss'))stems.push(raw.slice(0,-1),raw.slice(0,-2));
    const forms=new Set([key,...stems,...Array.from((exact?.[2]||'').matchAll(/(?:plural|participle|tense|comparative|superlative|form)[^.;]*?\bof\s+([A-Za-z]+(?:['-][A-Za-z]+)*)/g),x=>x[1].toLowerCase())]);
    let fallback=null;
    for(const word of forms){if(word===raw)continue;const entry=await this.lookup(word);if(entry?.[3]==='ko'&&this.validMeaning(entry[2]))return this.remember({entry,word});if(entry&&!fallback)fallback={entry,word};}
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
 if(!status)return;if(button)button.hidden=true;
 try{
   const count=window.webkit?.messageHandlers?.dictionaryStore?(await WordAheadDictionary.native('status')).entries:Object.keys(await WordAheadDictionary.loadBundled()).length;
   status.textContent=`내장 영한 사전 ${count.toLocaleString()}개 · 오프라인 사용 가능`;
 }catch{status.textContent='내장 영한 사전을 불러오지 못했습니다. 앱을 다시 열어주세요.';}
}
refreshOfflineDictionary();
