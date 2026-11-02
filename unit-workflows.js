/* Unit-specific records. Shared forms and lists; permissions are rechecked by SQL. */
(() => {
  'use strict';
  const TYPES = {
"pr_budget":{"name": "Bütçe ve Kararlar", "unit": "pr", "perm": "campaigns", "related": ["campaign", "event"], "money": true, "fields": {"currency": ["Para birimi", "text"], "reason": ["Gerekçe", "textarea"], "decision_note": ["Karar / düzeltme açıklaması", "textarea"], "attachment_url": ["Bütçe belgesi", "url"]}},"sponsor_budget":{"name": "Destek Değeri ve Bütçe", "unit": "sponsor", "perm": "sponsors", "related": ["sponsor", "event"], "money": true, "fields": {"currency": ["Para birimi", "text"], "in_kind": ["Ayni destek değeri / kapsamı", "textarea"], "decision_note": ["Karar / düzeltme açıklaması", "textarea"], "attachment_url": ["Belge", "url"]}},"club_request":{"name": "Başvurular ve Talepler", "unit": "clubs", "perm": "clubs", "related": ["candidate", "club"], "fields": {"purpose": ["Amaç", "textarea"], "target_unit": ["Yönlendirilen birim", "unit"], "decision_note": ["Karar / eksik bilgi gerekçesi", "textarea"], "attachment_url": ["Başvuru belgesi", "url"]}},"club_collaboration":{"name": "Etkinlik ve İş Birlikleri", "unit": "clubs", "perm": "clubs", "related": ["club", "event"], "fields": {"purpose": ["Amaç", "textarea"], "outcome": ["Sonuç", "textarea"], "attachment_url": ["Belge", "url"]}},"audit_report":{"name": "Denetim Raporları", "unit": "audit", "perm": "audit", "related": ["event", "club"], "fields": {"scope": ["Kapsam / incelenen kayıtlar", "textarea"], "participants": ["Katılımcılar", "textarea"], "observations": ["Gözlemler", "textarea"], "findings": ["Bulgular / sonuç", "textarea"], "attachment_url": ["Kanıt / rapor", "url"]}},
    center_message: { name:'Merkez Yönetim’e Bildirim', unit:null, perm:'team', related:['person','club'], fields:{recipient_group:['Alıcı grubu','select',{center:'Merkez Yönetim',heads:'Birim başkanları',unit:'Kendi birimim'}],attachment_url:['Ek bağlantısı','url'],event_id:['İlgili etkinlik','event']} },
    pr_request: { name:'Talep Kutusu',unit:'pr',perm:'campaigns',related:['club','event'],fields:{audience:['Hedef kitle','text'],purpose:['Amaç','textarea'],attachment_url:['Brief / ek','url']} },
    pr_material: { name:'İçerik ve Materyaller',unit:'pr',perm:'campaigns',related:['campaign'],fields:{version:['Sürüm','text'],platform:['Platform','text'],attachment_url:['Materyal bağlantısı','url']} },
    sponsor_followup: { name:'Görüşmeler ve Takipler',unit:'sponsor',perm:'sponsors',related:['sponsor'],fields:{participants:['Katılımcılar','text'],channel:['Görüşme kanalı','text'],outcome:['Sonuç','textarea'],next_step:['Sonraki adım','textarea'],attachment_url:['Ek','url']} },
    sponsor_offer: { name:'Teklifler ve Anlaşmalar',unit:'sponsor',perm:'sponsors',related:['sponsor','event'],money:true,fields:{scope:['Paket / destek kapsamı','textarea'],in_kind:['Ayni destek','textarea'],terms:['Koşullar','textarea'],renewal_date:['Yenileme tarihi','date'],currency:['Para birimi','text'],attachment_url:['Teklif / sözleşme','url']} },
    sponsor_package: { name:'Paketler ve Etkinlik Eşleştirme',unit:'sponsor',perm:'sponsors',related:['event'],money:true,fields:{scope:['Paket hakları ve kapsamı','textarea'],capacity:['Kontenjan','number'],remaining:['Kalan kontenjan','number'],attachment_url:['Paket belgesi','url']} },
    club_meeting: { name:'İletişim ve Takip',unit:'clubs',perm:'clubs',related:['candidate','club'],fields:{participants:['Katılımcılar','text'],location:['Konum','text'],meeting_url:['Meet / çevrim içi bağlantı','url'],purpose:['Görüşmenin amacı','textarea'],preparation:['Hazırlık notları','textarea'],outcome:['Görüşme sonucu','textarea'],next_step:['Sonraki takip adımı','textarea'],attachment_url:['Ek','url']} },
    club_event: { name:'Kulübe Özel Etkinlik Duyuruları',unit:'clubs',perm:'clubs',related:['club','candidate'],fields:{club_ids:['Ek hedef kulüpler','clubs'],location:['Yer','text'],meeting_url:['Etkinlik bağlantısı','url'],audience:['Hedef kitle','text'],attachment_url:['Görsel / ek','url']} },
    audit_plan: { name:'Denetim Planı',unit:'audit',perm:'audit',related:['event','club','unit'],fields:{scope:['Kapsam','textarea'],participants:['Denetim ekibi','text'],checklist:['Kontrol maddeleri (her satıra bir madde)','textarea'],attachment_url:['Plan / kanıt','url']} },
    audit_checklist: { name:'Kontrol Listeleri',unit:'audit',perm:'audit',related:['event'],fields:{scope:['Birim / süreç türü','text'],checklist:['Maddeler ve bulgular','textarea'],result:['Sonuç','select',{review:'İncelemede',ok:'Uygun',missing:'Eksik',na:'Uygulanamaz'}],evidence:['Kanıt açıklaması','textarea'],attachment_url:['Kanıt dosyası','url']} },
    audit_finding: { name:'Bulgular ve Düzeltici İşler',unit:'audit',perm:'audit',related:['event','club'],fields:{severity:['Önem','select',{low:'Düşük',medium:'Orta',high:'Yüksek',critical:'Kritik'}],target_unit:['İlgili birim','unit'],evidence:['Bulgu ve kanıt','textarea'],expected_action:['Beklenen düzeltme','textarea'],attachment_url:['Kanıt dosyası','url']} },
    audit_response: { name:'Birim Yanıtları',unit:'audit',perm:'audit',related:['finding'],fields:{evidence:['Yanıt / açıklama / ek bilgi','textarea'],attachment_url:['Yanıt belgesi','url']} },
    social_template: { name:'Şablonlar ve Kaynaklar',unit:'social',perm:'posts',related:['campaign','event'],fields:{platform:['Platform','text'],hashtags:['Etiket / hashtag','text'],cta:['CTA / yönlendirme','text'],alt_text:['Erişilebilirlik metni','textarea'],attachment_url:['Şablon / medya bağlantısı','url']} },
  };
  const STATUS={draft:'Taslak',open:'Açık',in_progress:'Sürüyor',needs_info:'Eksik bilgi bekliyor',approval:'Onayda',approved:'Onaylandı',rejected:'Reddedildi',completed:'Tamamlandı',cancelled:'İptal',planned:'Planlandı',published:'Yayımlandı',answered:'Yanıtlandı',closed:'Kapatıldı'};
  const RELATION={unit:'Birim',person:'Kişi',club:'Kulüp',candidate:'Aday kulüp',sponsor:'Firma',event:'Etkinlik',campaign:'Kampanya',finding:'Denetim bulgusu'};
  const BASE={social:'b-yayin',pr:'b-kampanyalar',sponsor:'b-sponsorlar',clubs:'b-kulupler',audit:'b-denetim'};
  let C;
  const caches=new Map();
  const view=k=>`b-work-${k}`;
  const readAllowed=k=>!!TYPES[k]&&(C.pending?.()||C.admin()||!!C.me().unit_id&&(!TYPES[k].unit||C.me().kind===TYPES[k].unit));
  const writeAllowed=k=>readAllowed(k)&&(C.admin()||C.me().is_head||(k==='center_message'?['team','posts','campaigns','sponsors','clubs','audit'].some(p=>C.me().perms?.includes(p)):C.me().perms?.includes(TYPES[k].perm)));
  const bucket=k=>{const key=`${C.me().id}:${k}`;if(!caches.has(key))caches.set(key,{q:'',status:'',page:0,archived:false,loading:false,loaded:false,rows:[],total:0,error:''});return caches.get(key);};
  const esc=x=>C.esc(x??'');
  const text=x=>esc(x).replace(/\n/g,'<br>');
  const datetime=x=>x?new Date(x).toLocaleString('tr-TR',{timeZone:'Europe/Istanbul'}):'—';
  const localDate=x=>x?new Date(new Date(x).getTime()-new Date(x).getTimezoneOffset()*60000).toISOString().slice(0,16):'';
  const iso=x=>x?new Date(x).toISOString():null;
  const select=(name,options,value)=>`<select name="${esc(name)}" ${({status:'Durum',mode:'Takvim görünümü',unit:'Birim filtresi',assignee:'Sorumlu',related_kind:'İlişki türü',archived:'Arşiv filtresi'})[name]?`aria-label="${({status:'Durum',mode:'Takvim görünümü',unit:'Birim filtresi',assignee:'Sorumlu',related_kind:'İlişki türü',archived:'Arşiv filtresi'})[name]}"`:''}>${Object.entries(options).map(([k,l])=>`<option value="${esc(k)}" ${k===value?'selected':''}>${esc(l)}</option>`).join('')}</select>`;
  const field=(label,html)=>C.field(label,html);
  const link=(url,label)=>/^https?:\/\//i.test(url||'')?`<a class="link-btn" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(label)}</a>`:'';
  const clubPicker=(key,label,value,clubs)=>{
    const ids=[...new Set(String(value||'').split(',').filter(Boolean))],selected=new Set(ids),known=new Set(clubs.map(c=>c.id));
    const missing=ids.filter(id=>!known.has(id));
    return `<fieldset class="field club-picker" data-wf-club-picker="${esc(key)}"><legend>${esc(label)}</legend><p class="muted" data-wf-club-count role="status">${ids.length?`${ids.length} kulüp seçili`:'Henüz hedef kulüp seçilmedi.'}</p><input type="search" data-wf-club-search="${esc(key)}" aria-label="${esc(label)} ara" placeholder="Kulüp veya üniversite ara" autocomplete="off"><div class="checks" data-wf-club-list="${esc(key)}">${missing.map(id=>`<label data-wf-club-option><input type="checkbox" name="extra_${esc(key)}" data-wf-club-choice value="${esc(id)}" checked> Kayıtlı kulüp (listede bulunamadı)</label>`).join('')}${clubs.map(c=>`<label data-wf-club-option><input type="checkbox" name="extra_${esc(key)}" data-wf-club-choice value="${esc(c.id)}" ${selected.has(c.id)?'checked':''}> ${esc(c.label)}</label>`).join('')}</div><p class="checks-empty" data-wf-club-empty hidden>Aramana uyan kulüp yok.</p></fieldset>`;
  };
  const load=async k=>{
    const b=bucket(k);if(b.loading)return;b.loading=true;b.error='';
    try {const r=await C.call('work_list',{kind:k,q:b.q,status:b.status,page:b.page,archived:b.archived});Object.assign(b,r,{loaded:true});}
    catch(e){b.error=e.message||'Kayıtlar yüklenemedi.';b.loaded=true;}
    finally{b.loading=false;if(C.currentView()===view(k))C.render();}
  };
  const refresh=k=>{bucket(k).loaded=false;return load(k);};
  const save=async(k,action,data)=>{const r=await C.call(action,data);await refresh(k);C.reloadNotifications();return r;};
  const render=k=>{
    if(!readAllowed(k))return C.empty('Bu sayfaya erişim yetkin yok.');
    if(C.pending?.())return C.empty('Yükleniyor…');
    const spec=TYPES[k],b=bucket(k);
    if(!b.loaded&&!b.loading)queueMicrotask(()=>load(k));
    const header=C.head(spec.name,k==='center_message'?'Gönderim durumu ve Merkez Yönetim yanıtları.':'Birim kayıtları, sorumlular, tarihler ve işlem geçmişi.',writeAllowed(k)?`<button class="btn" data-act="wf-new" data-id="${k}">${k==='center_message'?'Bildirim gönder':'Yeni kayıt'}</button>`:'');
    const filter=`<form data-wf-filter="${k}" class="toolbar"><input name="q" type="search" aria-label="Kayıt ara" placeholder="Başlık veya açıklama ara" maxlength="160" value="${esc(b.q)}">${select('status',{'':'Tüm durumlar',...STATUS},b.status)}${select('archived',{active:'Etkin kayıtlar',archived:'Arşivdekiler'},b.archived?'archived':'active')}<button class="btn ghost small" type="submit">Filtrele</button></form>`;
    if(b.loading||!b.loaded)return header+filter+C.empty('Yükleniyor…');
    if(b.error)return header+filter+`<div class="card"><p role="alert">${esc(b.error)}</p><button class="btn" data-act="wf-refresh" data-id="${k}">Tekrar dene</button></div>`;
    return header+filter+(b.rows.length?`<div class="stack">${b.rows.map(w=>`<article class="card item"><div class="meta"><span class="tag">${esc(STATUS[w.status]||w.status)}</span><span>${esc(w.related_label||'')}</span>${w.due_at&&new Date(w.due_at)<new Date()&&!['completed','closed','cancelled','published'].includes(w.status)?'<span class="tag no">Gecikti</span>':''}</div><h3>${esc(w.title)}</h3><p class="body">${text(w.body.slice(0,300))}${w.body.length>300?'…':''}</p><div class="meta"><span>${esc(w.assignee_name||'Sorumlu atanmadı')} · ${datetime(w.starts_at||w.created_at)}</span>${w.due_at?`<span>Son tarih: ${datetime(w.due_at)}</span>`:''}</div>${w.amount!==null?`<p class="body">Tutar: ${Number(w.amount).toLocaleString('tr-TR')} ${esc(w.data.currency||'TL')}</p>`:''}<div class="actions"><button class="btn small" data-act="wf-detail" data-id="${k}" data-sub="${w.id}">Detay ve yanıtlar</button>${writeAllowed(k)&&!w.archived_at&&['pr_request','pr_material','audit_finding'].includes(k)?`<button class="btn ghost small" data-act="wf-convert" data-id="${k}" data-sub="${w.id}">${k==='pr_material'?'Sosyal Medya’ya ilet':'Kampanya / görev oluştur'}</button>`:''}${writeAllowed(k)&&!w.archived_at&&(k!=='center_message'||C.admin()||w.created_by===C.me().id)?`<button class="btn ghost small" data-act="wf-edit" data-id="${k}" data-sub="${w.id}">Düzenle</button>`:''}${(C.admin()||C.me().is_head&&k!=='center_message')?`<button class="btn ghost small" data-act="wf-archive" data-id="${k}" data-sub="${w.id}">${w.archived_at?'Arşivden çıkar':'Arşivle'}</button>`:''}</div></article>`).join('')}</div>`:C.empty(b.archived?'Arşivde kayıt yok.':'Bu filtreye uyan kayıt yok.'))+
     `<div class="toolbar" style="margin-top:20px"><button class="btn ghost small" data-act="wf-page" data-id="${k}" data-sub="-1" ${b.page===0?'disabled':''}>Önceki</button><span>${b.total} kayıt · Sayfa ${b.page+1} / ${Math.max(1,Math.ceil(b.total/20))}</span><button class="btn ghost small" data-act="wf-page" data-id="${k}" data-sub="1" ${(b.page+1)*20>=b.total?'disabled':''}>Sonraki</button></div>`;
  };
  const edit=async(k,id)=>{
    if(!writeAllowed(k))return;
    const spec=TYPES[k],w=id?(await C.call('work_detail',{id})).record:{kind:k,data:{},status:'open'};
    const clubs=Object.values(spec.fields).some(f=>f[1]==='clubs')?await C.call('work_search',{workflow:k,kind:'club',q:''}):[];
    const events=Object.values(spec.fields).some(f=>f[1]==='event')?await C.call('work_search',{workflow:k,kind:'event',q:''}):[];
    const unit=C.units().find(u=>u.kind===spec.unit)||C.units().find(u=>u.id===C.me().unit_id);
    let statuses=STATUS;
    if(k==='center_message'&&!C.admin())statuses={[w.status]:STATUS[w.status]};
    else if(['sponsor_offer','pr_budget','sponsor_budget'].includes(k)&&!C.admin())statuses=Object.fromEntries(Object.entries(STATUS).filter(([s])=>!['approved','rejected','answered','closed'].includes(s)));
    C.openForm({title:id?'Kaydı düzenle':spec.name,submit:'Kaydet',fields:
      field('Başlık',`<input name="title" minlength="2" maxlength="160" required value="${esc(w.title||'')}">`)+field('Açıklama',`<textarea name="body" maxlength="10000" rows="4">${esc(w.body||'')}</textarea>`)+field('Durum',select('status',statuses,w.status))+
      (spec.related.length?`<fieldset class="field"><legend>${k==='center_message'?'İlgili kişi veya kulüp':'İlişkili kayıt'}</legend><div class="toolbar">${select('related_kind',{'':'Seçim yok',...Object.fromEntries(spec.related.map(x=>[x,RELATION[x]]))},w.related_kind||'')}<input name="related_search" placeholder="Ad yazarak ara" aria-label="İlişkili kayıt adı"><button type="button" class="btn ghost small" data-wf-search="${k}">Ara</button></div><select name="related_id" aria-label="Arama sonuçları"><option value="${esc(w.related_id||'')}">${w.related_id?'Mevcut bağlantıyı koru':'Kayıt seç'}</option></select><small data-wf-search-status role="status"></small></fieldset>`:'')+
      field('Sorumlu',select('assignee',{'':'Atanmadı',...Object.fromEntries((unit?.members||[]).map(m=>[m.id,m.name]))},w.assignee||''))+
      field('Başlangıç / görüşme zamanı',`<input type="datetime-local" name="starts_at" value="${localDate(w.starts_at)}">`)+field('Bitiş / takip tarihi',`<input type="datetime-local" name="due_at" value="${localDate(w.due_at)}">`)+
      (spec.money?field('Tutar',`<input type="number" min="0" max="99999999999999" step="0.01" name="amount" value="${esc(w.amount??'')}">`):'')+
      (id&&spec.fields.attachment_url?`<div class="field"><label>Dosya ekle (en fazla 10 MB)<input type="file" data-unit-upload="${esc(id)}" accept=".pdf,.jpg,.jpeg,.png,.webp,.txt,.docx,.xlsx,.pptx"></label><small role="status"></small></div>`:'')+
      Object.entries(spec.fields).map(([key,[label,type,options]])=>type==='clubs'?clubPicker(key,label,w.data[key],clubs):field(label,type==='textarea'?`<textarea name="extra_${key}" maxlength="5000" rows="3">${esc(w.data[key]||'')}</textarea>`:type==='event'?select(`extra_${key}`,{'':'Etkinlik seç',...Object.fromEntries(events.map(e=>[e.id,e.label]))},w.data[key]||'')+`<div class="toolbar"><input name="meta_search_${key}" aria-label="Etkinlik ara" placeholder="Etkinlik adı"><button type="button" class="btn ghost small" data-wf-meta="${key}" data-wf-kind="${k}">Ara</button><small role="status"></small></div>`:type==='unit'?select(`extra_${key}`,{'':'Birim seç',...Object.fromEntries(C.units().filter(u=>u.kind!=='board').map(u=>[u.id,u.name]))},w.data[key]||''):type==='select'?select(`extra_${key}`,options,w.data[key]||Object.keys(options)[0]):`<input name="extra_${key}" type="${type}" maxlength="5000" ${type==='number'?'min="0" step="1"':''} value="${esc(w.data[key]||'')}">`)).join(''),
      onSubmit:async fd=>{try{const val=n=>String(fd.get(n)||'');await save(k,'work_save',{id:id||null,kind:k,title:val('title'),body:val('body'),status:val('status'),assignee:val('assignee')||null,related_kind:val('related_kind')||null,related_id:val('related_id')||null,starts_at:iso(val('starts_at')),due_at:iso(val('due_at')),amount:val('amount')||null,data:Object.fromEntries(Object.keys(spec.fields).map(key=>[key,spec.fields[key][1]==='clubs'?fd.getAll(`extra_${key}`).join(','):val(`extra_${key}`)]))});C.toast('Kayıt kaydedildi.');return null;}catch(e){return e.message;}}
    });
  };
  const detail=async(k,id)=>{
    const {record:w,history}=await C.call('work_detail',{id}),spec=TYPES[k];
    C.openForm({title:w.title,submit:'Yanıt gönder',fields:`<div class="meta"><span class="tag">${esc(STATUS[w.status])}</span><span>${datetime(w.created_at)}</span></div><p class="body">${text(w.body)}</p>`+
      Object.entries(spec.fields).filter(([key])=>w.data[key]).map(([key,[label,type,options]])=>`<div class="field"><strong>${esc(label)}</strong><div>${type==='url'?link(w.data[key],label):text(type==='select'?options[w.data[key]]||w.data[key]:w.data[key])}</div></div>`).join('')+
      `<details open><summary>Yanıtlar ve geçmiş (${history.length})</summary>${history.map(h=>`<div class="card item"><div class="meta">${esc(h.actor_name)} · ${datetime(h.created_at)}</div><strong>${esc(h.action)}</strong>${h.body?`<p class="body">${text(h.body)}</p>`:''}${h.snapshot?`<details><summary>Bu sürüm</summary><p>${esc(h.snapshot.title)} · ${esc(STATUS[h.snapshot.status]||h.snapshot.status)}</p><p class="body">${text(h.snapshot.body)}</p>${h.snapshot.due_at?`<p>Son tarih: ${datetime(h.snapshot.due_at)}</p>`:''}</details>`:''}</div>`).join('')}</details>`+field('Yanıt / ilerleme notu','<textarea name="body" required maxlength="5000" rows="4"></textarea>'),
      onSubmit:async fd=>{try{await save(k,'work_reply',{id,body:String(fd.get('body')||'')});C.toast('Yanıt gönderildi.');return null;}catch(e){return e.message;}}
    });
  };
  const installDemo=D=>{
    const store=()=>{const s=D.store();s.workItems||=[];s.workHistory||=[];return s;};
    const allowed=(k,c,write=false)=>!!TYPES[k]&&(c.admin||!!c.unit&&(!TYPES[k].unit||c.kind===TYPES[k].unit)&&(!write||c.head||(k==='center_message'?['team','posts','campaigns','sponsors','clubs','audit'].some(c.has):c.has(TYPES[k].perm))));
    const visible=(w,c)=>c.admin||['audit_finding','club_request'].includes(w.kind)&&w.data.target_unit===c.unit||allowed(w.kind,c)&&(w.kind!=='center_message'?w.unit_id===c.unit&&(TYPES[w.kind].unit!=='audit'||c.has('audit')||c.has('audit_assign')||w.assignee===c.id):w.created_by===c.id||w.related_kind==='person'&&w.related_id===c.id||w.data.recipient_group==='heads'&&c.head&&c.kind!=='board'||w.data.recipient_group==='unit'&&w.unit_id===c.unit);
    const log=(w,c,action,body)=>store().workHistory.push({id:D.uid(),item_id:w.id,actor:c.id,actor_name:D.name(c.id),action,body:body||null,snapshot:body?null:JSON.parse(JSON.stringify(w)),created_at:D.stamp()});
    const find=(id,c)=>{const w=store().workItems.find(w=>w.id===id);if(!w||!visible(w,c))throw new Error('Kayıt bulunamadı.');return w;};
    const source=(kind,c)=>{
      const db=D.db();
      if(kind==='unit')return db.units.filter(u=>u.kind!=='board').map(u=>({id:u.id,label:u.name}));
      if(kind==='person')return db.units.flatMap(u=>u.members.filter(m=>m.status==='active').map(m=>({id:m.id,label:m.full_name})));
      if(kind==='club')return db.clubs.map(x=>({id:x.id,label:x.name}));
      if(kind==='candidate'&&(c.admin||c.kind==='clubs'))return (store().clubnet?.candidates||[]).map(x=>({id:x.id,label:x.name}));
      if(kind==='sponsor'&&(c.admin||c.kind==='sponsor'))return (store().sponsors?.rows||store().sponsors||[]).map(x=>({id:x.id,label:x.brand}));
      if(kind==='event')return db.events.map(x=>({id:x.id,label:x.title}));
      if(kind==='campaign'&&(c.admin||c.kind==='pr'||c.kind==='social'))return (store().campaigns||[]).map(x=>({id:x.id,label:x.title}));
      if(kind==='finding'&&(c.admin||c.kind==='audit'))return store().workItems.filter(w=>w.kind==='audit_finding'&&visible(w,c)).map(w=>({id:w.id,label:w.title}));
      return [];
    };
    D.registry.candidate_join=(p,c)=>{
      if(!(c.admin||c.kind==='clubs'&&c.has('clubs')))throw new Error('Kulüp kabul yetkin yok.');
      const candidate=store().clubnet.candidates.find(x=>x.id===p.id);if(!candidate)throw new Error('Aday bulunamadı.');
      if(candidate.club_id)return {id:candidate.id,club_id:candidate.club_id};
      if(!candidate.university?.trim())throw new Error('Adayın üniversitesini önce doldur.');
      const matches=D.db().clubs.filter(x=>x.name.trim().toLocaleLowerCase('tr')===candidate.name.trim().toLocaleLowerCase('tr')&&(x.uni||'').trim().toLocaleLowerCase('tr')===candidate.university.trim().toLocaleLowerCase('tr'));
      if(matches.length>1)throw new Error('Birden çok eşleşen kulüp var.');
      const target=matches[0]||{id:candidate.id,name:candidate.name,uni:candidate.university,visible:false,joinedAt:D.stamp()};
      if(!matches.length)D.db().clubs.push(target);candidate.club_id=target.id;candidate.status='added';
      store().workItems.filter(w=>w.kind==='club_meeting'&&w.related_id===candidate.id&&w.status==='completed').forEach(w=>syncClub(w,c));
      return {id:candidate.id,club_id:target.id};
    };
    const syncClub=(w,c)=>{
      const club=w.related_kind==='club'?w.related_id:store().clubnet?.candidates.find(x=>x.id===w.related_id)?.club_id;if(!club)return;
      if(w.kind==='club_meeting'&&w.status==='completed'){
        const contacts=store().clubnet.contacts,old=contacts.find(x=>x.source_work_id===w.id),row={id:old?.id||D.uid(),club_id:club,at:(w.starts_at||D.stamp()).slice(0,10),kind:'meeting',note:[w.title,w.data.outcome,w.data.next_step].filter(Boolean).join('\n'),created_by:c.id,source_work_id:w.id};
        if(old)Object.assign(old,row);else contacts.push(row);
      }
      if(w.kind==='center_message'||w.kind==='club_event'&&w.status==='published'){
        D.db().notifications||=[];store().deliveries||={};for(const recipient of new Set([club,...(w.kind==='club_event'?(w.data.club_ids||'').split(',').filter(Boolean):[])])){const key=w.id+':'+recipient;if(store().deliveries[key])continue;store().deliveries[key]=true;D.db().notifications.unshift({id:D.uid(),recipientClubId:recipient,type:'unit_club_event',title:w.title,body:w.body,actionable:false,resolved:true,createdAt:D.stamp()});}
      }
    };
    D.registry.work_convert=(p,c)=>{const w=find(p.id,c);if(!allowed(w.kind,c,true))throw new Error('Dönüştürme yetkin yok.');store().conversions||={};const key=w.id+':'+p.target;if(store().conversions[key])return {id:store().conversions[key]};let result;if(p.target==='campaign'&&w.kind==='pr_request'){D.registry.camp_save({title:w.title,idea:w.body,goal:w.data.purpose},c);result={id:store().campaigns[0].id};}else if(p.target==='task'&&['pr_request','audit_finding'].includes(w.kind))result=D.registry.task_create({title:w.title,description:w.body,assignee:p.assignee,unit_id:w.unit_id},c);else if(p.target==='social'&&w.kind==='pr_material'){D.registry.post_request({title:w.title,brief:w.body+'\n'+(w.data.attachment_url||'')},c);result={id:store().posts[0]?.id};}else throw new Error('Bu dönüşüm desteklenmiyor.');store().conversions[key]=result?.id;return result;};
    D.registry.work_search=(p,c)=>{if(!allowed(p.workflow,c,true))throw new Error('Arama yetkin yok.');return source(p.kind,c).filter(x=>x.label.toLocaleLowerCase('tr-TR').includes((p.q||'').toLocaleLowerCase('tr-TR'))).slice(0,30);};
    D.registry.work_list=(p,c)=>{
      if(!allowed(p.kind,c))throw new Error('Bu sayfaya erişim yetkin yok.');
      const all=store().workItems.filter(w=>w.kind===p.kind&&visible(w,c)&&!!w.archived_at===!!p.archived&&(!p.status||w.status===p.status)&&[w.title,w.body].join(' ').toLocaleLowerCase('tr-TR').includes((p.q||'').toLocaleLowerCase('tr-TR'))).sort((a,b)=>b.updated_at.localeCompare(a.updated_at)||a.id.localeCompare(b.id));
      const page=Math.max(0,Number(p.page)||0);
      return {rows:all.slice(page*20,page*20+20).map(w=>({...w,creator_name:D.name(w.created_by),assignee_name:D.name(w.assignee),related_label:source(w.related_kind,c).find(x=>x.id===w.related_id)?.label||''})),total:all.length,page};
    };
    D.registry.work_detail=(p,c)=>({record:find(p.id,c),history:store().workHistory.filter(h=>h.item_id===p.id)});
    D.registry.work_save=(p,c)=>{
      if(!allowed(p.kind,c,true))throw new Error('Kayıt düzenleme yetkin yok.');
      const old=p.id?find(p.id,c):null,spec=TYPES[p.kind];
      if(old&&(old.kind!==p.kind||old.archived_at))throw new Error('Kayıt değiştirilemez.');
      if(p.kind==='center_message'&&!c.admin&&(old&&old.created_by!==c.id||p.status!==(old?.status||'open')))throw new Error('Bu işlem için Merkez yetkisi gerekir.');
      if(!c.admin&&['center_message','sponsor_offer','pr_budget','sponsor_budget'].includes(p.kind)&&['approved','rejected','answered','closed'].includes(p.status))throw new Error('Karar yetkisi Merkez Yönetim’dedir.');
      if(!Object.hasOwn(STATUS,p.status))throw new Error('Geçersiz durum.');
      if(p.title.trim().length<2||p.title.length>160)throw new Error('Başlık 2–160 karakter olmalı.');
      for(const [k,v] of Object.entries(p.data||{})){if(!spec.fields[k]||typeof v!=='string'||v.length>5000)throw new Error('Geçersiz kayıt alanı.');if(k.endsWith('_url')&&v&&!/^https?:\/\/[^\s"'<>]+$/i.test(v))throw new Error('Geçerli bağlantı gir.');}
      if(p.related_id&&!source(p.related_kind,c).some(x=>x.id===p.related_id))throw new Error('İlişkili kayıt bulunamadı.');
      if(['club_meeting','club_event','sponsor_followup','sponsor_offer','audit_response'].includes(p.kind)&&!p.related_id)throw new Error('İlişkili kaydı seç.');
      const unit=spec.unit?D.db().units.find(u=>u.kind===spec.unit)?.id:old?.unit_id||c.unit;
      if(p.assignee&&!D.db().units.some(u=>u.id===unit&&u.members.some(m=>m.id===p.assignee&&m.status==='active')))throw new Error('Sorumlu ilgili birimden olmalı.');
      if(p.starts_at&&p.due_at&&p.due_at<p.starts_at)throw new Error('Bitiş başlangıçtan önce olamaz.');
      const w={...old,...p,id:old?.id||D.uid(),unit_id:unit,created_by:old?.created_by||c.id,created_at:old?.created_at||D.stamp(),updated_at:D.stamp(),archived_at:null,amount:p.amount?Number(p.amount):null};
      if(old)Object.assign(old,w);else store().workItems.push(w);syncClub(w,c);log(w,c,old?'Kayıt güncellendi':'Kayıt oluşturuldu');
      if(p.kind==='center_message'&&!old){D.notify(null,null,null,true,'center_message','Merkez’e yeni bildirim',w.title,view(w.kind),w.id);if(w.related_kind==='person')D.notify(w.related_id,null,null,false,'center_message','Sana yöneltilen bildirim',w.title,view(w.kind),w.id);}
      return w;
    };
    D.registry.work_reply=(p,c)=>{const w=find(p.id,c);if(w.archived_at)throw new Error('Önce kaydı arşivden çıkar.');if(!p.body?.trim())throw new Error('Yanıt boş olamaz.');log(w,c,'Yanıt',p.body);if(w.kind==='center_message'){w.status=c.admin?'answered':'open';w.updated_at=D.stamp();D.notify(c.admin?w.created_by:null,null,null,!c.admin,'center_reply',c.admin?'Merkez Yönetim yanıtladı':'Bildirime yeni yanıt',w.title,view(w.kind),w.id);}return {id:w.id};};
    D.registry.work_archive=(p,c)=>{const w=find(p.id,c);if(!(c.admin||c.head&&w.kind!=='center_message'))throw new Error('Arşivleme yetkin yok.');w.archived_at=p.restore?null:D.stamp();w.updated_at=D.stamp();log(w,c,p.restore?'Arşivden çıkarıldı':'Arşivlendi');return {id:w.id};};
  };

  window.UniPaktWorkflows={
    types:TYPES,openRecord:detail,
    invalidate(){for(const b of caches.values())b.loaded=false;},
    baseView(v){return BASE[TYPES[v.replace(/^b-work-/,'')]?.unit]||v;},
    unitLinks(kind){return Object.entries(TYPES).filter(([k,s])=>s.unit===kind&&readAllowed(k)).map(([k,s])=>`<button type="button" class="nav-item nav-sub-item${C.currentView()===view(k)?' active':''}" data-go="${view(k)}">${esc(s.name)}</button>`).join('');},
    install(context){
      C=context;
      if(C.demo?.enabled)installDemo(C.demo);
      for(const [k,spec] of Object.entries(TYPES))C.register(view(k),{label:()=>spec.name,group:'birim',order:25,allow:()=>readAllowed(k),render:()=>render(k)});
      C.shared.add(view('center_message'));
      Object.assign(C.actions,{
        'wf-convert':async(k,id)=>{const target=k==='pr_material'?'social':k==='pr_request'?'campaign':'task';const team=C.units().find(u=>u.kind===TYPES[k].unit)?.members||[];C.openForm({title:'İlişkili kayıt oluştur',submit:'Oluştur',fields:k==='pr_request'?field('Hedef',select('target',{campaign:'Kampanya',task:'Görev'},'campaign'))+field('Görev sorumlusu',select('assignee',Object.fromEntries(team.map(m=>[m.id,m.name])),'')):target==='task'?field('Sorumlu',select('assignee',Object.fromEntries(team.map(m=>[m.id,m.name])),'')):'<p>Materyal, Sosyal Medya talep kutusuna gönderilir.</p>',onSubmit:async fd=>{try{await C.call('work_convert',{id,target:String(fd.get('target')||target),assignee:String(fd.get('assignee')||'')||null});C.reloadNotifications();C.toast('İlişkili kayıt oluşturuldu.');return null;}catch(e){return e.message;}}});},
        'wf-new':k=>edit(k), 'wf-edit':edit, 'wf-detail':detail, 'wf-refresh':refresh,
        'wf-page':(k,step)=>{bucket(k).page=Math.max(0,bucket(k).page+Number(step));return refresh(k);},
        'wf-archive':async(k,id)=>{const w=bucket(k).rows.find(x=>x.id===id);if(!w)return;await save(k,'work_archive',{id,restore:!!w.archived_at});C.toast(w.archived_at?'Kayıt geri alındı.':'Kayıt arşivlendi.');},
      });
      document.addEventListener('submit',e=>{const k=e.target.dataset.wfFilter;if(!k)return;e.preventDefault();const fd=new FormData(e.target),b=bucket(k);Object.assign(b,{q:String(fd.get('q')||''),status:String(fd.get('status')||''),archived:String(fd.get('archived')||'')==='archived',page:0});refresh(k);});
      document.addEventListener('input',e=>{const search=e.target.closest('[data-wf-club-search]');if(!search)return;const picker=search.closest('[data-wf-club-picker]'),q=search.value.trim().toLocaleLowerCase('tr-TR');let visible=0;picker.querySelectorAll('[data-wf-club-option]').forEach(option=>{const show=!q||option.textContent.toLocaleLowerCase('tr-TR').includes(q);option.hidden=!show;if(show)visible+=1;});picker.querySelector('[data-wf-club-empty]').hidden=visible>0;});
      document.addEventListener('change',e=>{const choice=e.target.closest('[data-wf-club-choice]');if(!choice)return;const picker=choice.closest('[data-wf-club-picker]'),count=picker.querySelectorAll('[data-wf-club-choice]:checked').length;picker.querySelector('[data-wf-club-count]').textContent=count?`${count} kulüp seçili`:'Henüz hedef kulüp seçilmedi.';});
      document.addEventListener('click',async e=>{const button=e.target.closest('[data-wf-search]');if(!button)return;const form=button.closest('form'),k=button.dataset.wfSearch,status=form.querySelector('[data-wf-search-status]');button.disabled=true;status.textContent='Aranıyor…';try{const items=await C.call('work_search',{workflow:k,kind:form.elements.related_kind.value,q:form.elements.related_search.value});form.elements.related_id.innerHTML='<option value="">Kayıt seç</option>'+items.map(x=>`<option value="${esc(x.id)}">${esc(x.label)}</option>`).join('');status.textContent=items.length?`${items.length} sonuç`:'Kayıt bulunamadı.';}catch(error){status.textContent=error.message;}finally{button.disabled=false;}});
      document.addEventListener('click',async e=>{const b=e.target.closest('[data-wf-meta]');if(!b)return;const form=b.closest('form'),key=b.dataset.wfMeta,status=b.parentElement.querySelector('[role="status"]');b.disabled=true;try{const rows=await C.call('work_search',{workflow:b.dataset.wfKind,kind:'event',q:form.elements['meta_search_'+key].value});form.elements['extra_'+key].innerHTML='<option value="">Seç</option>'+rows.map(x=>`<option value="${esc(x.id)}">${esc(x.label)}</option>`).join('');status.textContent=rows.length+' sonuç';}catch(error){status.textContent=error.message;}finally{b.disabled=false;}});
      document.addEventListener('change',e=>{if(e.target.name==='related_kind'&&e.target.form?.querySelector('[data-wf-search]'))e.target.form.elements.related_id.innerHTML='<option value="">Kayıt seç</option>';});
    }
  };
})();
