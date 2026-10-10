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
  async show(raw,key) {
    const selection=currentWord;
    try {
      const entry=await this.lookup(raw)||await this.lookup(key);
      if(currentWord!==selection||!entry)return;
      selection.entry=entry;
      $('#sheet-part').textContent=entry[1];$('#sheet-phonetic').textContent=entry[0]||'발음 기호 미등록';
      $('#sheet-meaning').textContent=entry[2];
      $('#dictionary-source').href=`https://${entry[3]==='ko'?'ko':'en'}.wiktionary.org/wiki/`+encodeURIComponent(raw.toLowerCase());
      const existing=saved.find(x=>x.word===key);
      if(existing){existing.definition=entry[2];existing.phonetic=entry[0];existing.part=entry[1];persist();}
    }catch{if(currentWord===selection&&!DICTIONARY[key])$('#sheet-meaning').textContent='내장 사전을 불러올 수 없습니다.';}
  }
};
