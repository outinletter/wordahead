const WordAheadDictionary = {
  shards:new Map(), pending:new Map(),
  install(id,entries) {this.shards.delete(id);this.shards.set(id,entries);while(this.shards.size>8)this.shards.delete(this.shards.keys().next().value);},
  async lookup(word) {
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
    if(exact?.[3]==='ko')return {entry:exact,word:raw};
    const forms=new Set([key,...Array.from((exact?.[2]||'').matchAll(/(?:plural|participle|tense|comparative|superlative|form)[^.;]*?\bof\s+([A-Za-z]+(?:['-][A-Za-z]+)*)/g),x=>x[1].toLowerCase())]);
    let fallback=null;
    for(const word of forms){if(word===raw)continue;const entry=await this.lookup(word);if(entry?.[3]==='ko')return {entry,word};if(entry&&!fallback)fallback={entry,word};}
    return exact?{entry:exact,word:raw}:fallback;
  },
  onlineCache:new Map(),
  async online(word,lang,signal) {
    const cacheKey=`${lang}:${word}`;
    if(this.onlineCache.has(cacheKey))return this.onlineCache.get(cacheKey);
    const params=new URLSearchParams({action:'parse',page:word,prop:'text',format:'json',origin:'*',redirects:'1',disableeditsection:'1',disablelimitreport:'1'});
    const response=await fetch(`https://${lang}.wiktionary.org/w/api.php?${params}`,{signal,credentials:'omit'});
    if(!response.ok)throw new Error('온라인 사전 연결 실패');
    const data=await response.json();
    if(data.error){if(data.error.code==='missingtitle'){this.onlineCache.set(cacheKey,null);return null;}throw new Error(data.error.info);}
    const doc=new DOMParser().parseFromString(data.parse?.text?.['*']||'','text/html');
    let english=false,part='',phonetic='',definitions=[];
    for(const node of doc.querySelectorAll('h2,h3,h4,.IPA,ol > li')){
      if(node.tagName==='H2'){english=node.textContent.trim()===(lang==='ko'?'영어':'English');continue;}
      if(!english)continue;
      if(/^H[34]$/.test(node.tagName)){part=node.textContent.trim();continue;}
      if(node.classList.contains('IPA')){phonetic=phonetic||node.textContent.trim();continue;}
      if(node.closest('li li')||node.closest('.NavFrame,.quotations'))continue;
      const copy=node.cloneNode(true);copy.querySelectorAll('ul,ol,dl,sup,.HQToggle,.citation-whole').forEach(x=>x.remove());
      const text=copy.textContent.replace(/\s+/g,' ').trim();
      if(text&&definitions.length<3)definitions.push(text);
    }
    const result=definitions.length?{word,entry:[phonetic,part,definitions.join('; '),lang],online:true}:null;
    this.onlineCache.set(cacheKey,result);while(this.onlineCache.size>200)this.onlineCache.delete(this.onlineCache.keys().next().value);
    return result;
  },
  async resolve(raw,key) {
    const local=await this.preferred(raw,key);
    if(navigator.onLine===false)return local;
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),8000);
    try{
      for(const word of new Set([raw.toLowerCase().replaceAll('’',"'"),local?.word,key])){
        if(!word)continue;
        const result=await this.online(word,'ko',controller.signal);if(result){result.entry[0]=result.entry[0]||local?.entry[0]||'';return result;}
      }
      if(local?.entry[3]==='ko')return local;
      return await this.online(raw.toLowerCase(),'en',controller.signal)||local;
    }catch{return local;}finally{clearTimeout(timer);}
  },
  async show(raw,key) {
    const selection=currentWord;
    try {
      const result=await this.resolve(raw,key);
      if(currentWord!==selection)return;
      if(!result){if(!selection.entry?.[2])$('#sheet-meaning').textContent='내장 사전에 수록되지 않은 단어입니다.';return;}
      const {entry,word}=result;
      selection.entry=entry;
      $('#sheet-part').textContent=entry[1];$('#sheet-phonetic').textContent=entry[0]||'';
      $('#sheet-meaning').textContent=entry[2];
      $('#dictionary-source').href=`https://${entry[3]==='ko'?'ko':'en'}.wiktionary.org/wiki/`+encodeURIComponent(word);
      $('#dictionary-source').textContent=`${result.online?'온라인':'내장'} Wiktionary · ${word}`;$('#dictionary-source').hidden=false;
      const existing=saved.find(x=>x.word===key);
      if(existing){existing.definition=entry[2];existing.phonetic=entry[0];existing.part=entry[1];persist();}
    }catch{if(currentWord===selection&&!DICTIONARY[key])$('#sheet-meaning').textContent='내장 사전을 불러올 수 없습니다.';}
  }
};
