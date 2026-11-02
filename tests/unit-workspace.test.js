import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

// Platform primitives only are fixtures. Real migrations and RPCs run in PostgreSQL.
const fixture = `
create role anon; create role authenticated; create role service_role;
create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.clubs(id uuid primary key default gen_random_uuid(), name text, university text, category text, visible boolean default true, created_at timestamptz default now());
create table public.notifications(id uuid primary key default gen_random_uuid(),recipient_club_id uuid,recipient_role text,type text,title text,body text,actionable boolean,resolved boolean);
create table public.profiles(id uuid primary key references auth.users(id), role text, club_id uuid references public.clubs(id),full_name text, username text,avatar_url text,member_title text);
create table public.events(id uuid primary key default gen_random_uuid(),club_id uuid references public.clubs(id),title text,event_date date,event_time text,place text,status text);
create table public.announcements(id uuid primary key default gen_random_uuid(),club_id uuid,title text,body text,status text,decided_at timestamptz,created_at timestamptz default now());
create table public.activity_log(id uuid primary key default gen_random_uuid(),club_id uuid,actor_id uuid,actor_name text,actor_title text,action text,target text,created_at timestamptz default now());
create table public.site_theme(id int,colors text[],angle int,on_dark text,on_light text,on_accent text,updated_at timestamptz,updated_by uuid);
create function public.is_admin() returns boolean language sql stable security definer as $$select exists(select 1 from public.profiles where id=auth.uid() and role='admin')$$;
create function public.mfa_ok() returns boolean language sql stable as $$select coalesce(current_setting('test.mfa',true),'')='yes'$$;
create function public.log_activity(text,text,uuid default null) returns void language sql as $$select$$;
`;
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const migrationNames = ['20261101_units','20261101_unit_kinds','20261102_unit_workspace','20261103_unit_approvals_posts_campaigns','20261104_unit_sponsors_clubs_audit_support','20261105_audit_ladder_fix','20261106_sponsor_admin_management','20261107_unit_workspace_foundation','20261108_unit_workflows','20261109_unit_record_details','20261110_unit_private_files','20261111_unit_shared_integrity','20261112_unit_routing_and_documents'];
const missingMigrations = migrationNames.filter(name => !existsSync(new URL(`../supabase/migrations/${name}.sql`,import.meta.url)));
const migration = name => readFileSync(new URL(`../supabase/migrations/${name}.sql`,import.meta.url),'utf8');
test('workspace authorization, task history and admin actions', {skip: missingMigrations.length ? `SQL migration files are delivered separately; missing locally: ${missingMigrations.join(', ')}` : false}, async t => {
 const db = new PGlite();
 try {
  await db.exec(fixture);
  for(const name of migrationNames) {
   try {await db.exec(migration(name));} catch(e){throw new Error(`${name}: ${e.message} at ${e.position}: ${migration(name).slice(Number(e.position)-180,Number(e.position)+180)} ${e.internalQuery || ""}`);}
  }
  const sql = async (text,params=[]) => (await db.query(text,params)).rows;
  const rpc = async (action,data={}) => (await sql('select public.uw($1,$2::jsonb) as value',[action,JSON.stringify(data)]))[0].value;
  const login = async (n,mfa=true) => sql("select set_config('test.uid',$1,false),set_config('test.mfa',$2,false)",[id(n),mfa?'yes':'no']);
  const unit = async kind => (await sql('select id from public.units where kind=$1',[kind]))[0].id;
  const social=await unit('social'),pr=await unit('pr');
  await sql("insert into public.units(name,kind) values ('Eski YK','board')");
  for(const [n,kind,head] of [[1,null,false],[2,'social',true],[3,'social',false],[4,'pr',true],[5,'board',true],[6,'audit',true],[7,'pr',false],[8,'clubs',true],[9,'sponsor',true],[11,'audit',false]]) {
   await sql('insert into auth.users values($1)',[id(n)]);
   await sql('insert into public.profiles(id,role,full_name) values($1,$2,$3)',[id(n),kind?'unit':'admin',`User ${n}`]);
   if(kind) {const u=await unit(kind);await sql('insert into public.unit_members(user_id,unit_id,role_id,is_head) select $1,$2,id,$3 from public.unit_roles where unit_id=$2 and name=$4',[id(n),u,head,head?'Birim Başkanı':'Üye']);}
  }
  let task;
  await t.test('admin creates task, history and assignment notification',async()=>{
   await login(1);task=(await rpc('task_create',{unit_id:social,assignee:id(2),title:'İçerik planı',priority:'high',attachment_url:'https://example.com/brief'})).id;
   assert.equal((await sql('select priority from public.unit_tasks where id=$1',[task]))[0].priority,'high');
   assert.equal((await sql('select count(*)::int n from public.unit_task_history where task_id=$1',[task]))[0].n,1);
   assert.equal((await sql('select count(*)::int n from public.unit_notifications where recipient_user=$1',[id(2)]))[0].n,1);
  });
  await t.test('unrelated unit and unassigned teammate cannot mutate/comment',async()=>{
   for(const n of [4,3]) {await login(n);await assert.rejects(rpc('task_update',{id:task,progress:'blocked'}),/Görev bulunamadı/);await assert.rejects(rpc('task_comment',{id:task,body:'No'}),/Görev bulunamadı/);}
  });
  await t.test('assigned head comments; admin changes deadline; actors are retained',async()=>{
   await login(2);await rpc('task_comment',{id:task,body:'Hazırlık sürüyor'});await rpc('task_update',{id:task,progress:'in_progress'});
   await login(1);await rpc('task_update',{id:task,due_date:'2026-12-01'});
   const rows=await sql('select actor_id,body,changes from public.unit_task_history where task_id=$1',[task]);
   assert.ok(rows.some(x=>x.actor_id===id(2)&&x.body==='Hazırlık sürüyor'));
   assert.ok(rows.some(x=>x.actor_id===id(1)&&x.changes?.due_date?.after==='2026-12-01'));
  });
  await t.test('member updates own progress, cannot change priority/deadline or assign across units',async()=>{
   await login(2);const own=(await rpc('task_create',{assignee:id(3),title:'Metin hazırla'})).id;
   await login(3);await rpc('task_update',{id:own,progress:'in_progress'});
   await assert.rejects(rpc('task_update',{id:own,priority:'urgent'}),/yalnızca/);
   await assert.rejects(rpc('task_update',{id:own,due_date:'2026-12-02'}),/yalnızca/);
   await assert.rejects(rpc('task_create',{unit_id:pr,assignee:id(7),title:'Yetkisiz atama'}),/yetkisi/);
  });
  await t.test('MFA remains mandatory for administrators',async()=>{
   await login(1,false);await assert.rejects(rpc('task_update',{id:task,title:'No'}),/doğrulama/);
  });
  await t.test('board authority follows active heads; legacy board and members cannot approve',async()=>{
   for(const [n,expected] of [[2,true],[4,true],[3,false],[5,false]]){await login(n);assert.equal((await sql('select public.uw_board() as ok'))[0].ok,expected);}
   await sql("update public.unit_members set status='passive' where user_id=$1",[id(4)]);await login(4);assert.equal((await sql('select public.uw_board() as ok'))[0].ok,false);
   await sql("update public.unit_members set status='active' where user_id=$1",[id(4)]);
  });
  await t.test('admin creates/submits/approves PR campaign; active heads receive requests',async()=>{
   await login(1);const c=(await rpc('camp_save',{title:'Kampüs kampanyası',goal:'Tanıtım'})).id;await rpc('camp_submit',{id:c});
   const r=(await sql('select id from public.unit_requests where ref_id=$1',[c]))[0].id;
   const notifications=await sql("select recipient_user from public.unit_notifications where type='request'");
   assert.ok(notifications.some(x=>x.recipient_user===id(2)));assert.ok(!notifications.some(x=>x.recipient_user===id(5)));
   await rpc('req_decide',{id:r,decision:'approved'});assert.equal((await sql('select status from public.pr_campaigns where id=$1',[c]))[0].status,'approved');
  });
  await t.test('admin edits social content using social assignee; PR assignee rejected',async()=>{
   await login(1);await rpc('post_request',{title:'Yeni yayın',brief:'Brief'});const post=(await sql("select id from public.social_posts where title='Yeni yayın'"))[0].id;
   await rpc('post_save',{id:post,title:'Yeni yayın',body:'İçerik',platforms:['instagram'],assignee:id(2)});
   await assert.rejects(rpc('post_save',{id:post,title:'Yeni yayın',assignee:id(4)}),/Sosyal Medya/);
  });
  await t.test('audit includes central events; admin assigns audit staff only',async()=>{
   await login(1);const e=(await sql("insert into public.events(title,event_date,status) values('Merkez etkinliği','2026-12-02','draft') returning id"))[0].id;
   await rpc('audit_assign',{event_id:e,user_id:id(6)});await assert.rejects(rpc('audit_assign',{event_id:e,user_id:id(2)}),/Denetim/);
   await login(6);assert.ok((await sql('select public.uwr_audit() as result'))[0].result.events.some(x=>x.id===e));
  });
  await t.test('authenticated users cannot call helpers or read history table directly',async()=>{
   for(const sig of ['public.uwa_task_update(jsonb)','public.uwa_task_comment(jsonb)','public.uw_board()']) assert.equal((await sql("select has_function_privilege('authenticated',$1,'EXECUTE') as ok",[sig]))[0].ok,false);
   assert.equal((await sql("select has_table_privilege('authenticated','public.unit_task_history','SELECT') as ok"))[0].ok,false);
  });
  await t.test('center messages remain private and support a two-way reply',async()=>{
   await login(2);const w=await rpc('work_save',{kind:'center_message',title:'Ekip için talep',body:'Ayrıntılar',status:'open',data:{recipient_group:'center'}});
   await login(4);await assert.rejects(rpc('work_detail',{id:w.id}),/Kayıt bulunamadı/);
   await login(1);await rpc('work_reply',{id:w.id,body:'Talep incelendi.'});
   await login(2);const detail=await rpc('work_detail',{id:w.id});assert.equal(detail.record.status,'answered');assert.ok(detail.history.some(h=>h.body==='Talep incelendi.'));
   await assert.rejects(rpc('work_save',{...w,status:'closed'}),/Merkez/);
   await login(3);await assert.rejects(rpc('work_save',{kind:'center_message',title:'Yetkisiz talep',data:{}}),/yetkin yok/);
  });
  await t.test('candidate meetings retain relationships, timestamps, history and archives',async()=>{
   await login(8);const candidate=(await sql("insert into public.club_candidates(name,university) values('Jeoloji Topluluğu','İÜC') returning id"))[0].id;
   const w=await rpc('work_save',{kind:'club_meeting',title:'Tanışma görüşmesi',status:'planned',related_kind:'candidate',related_id:candidate,starts_at:'2026-12-02T10:00:00Z',due_at:'2026-12-03T10:00:00Z',data:{meeting_url:'https://meet.google.com/example',participants:'Başkan ve ekip',outcome:'',next_step:'Tekrar görüş'}});
   assert.equal(w.related_id,candidate);
   await rpc('work_save',{...w,status:'completed',data:{...w.data,outcome:'Olumlu görüşme'}});
   assert.equal((await rpc('work_detail',{id:w.id})).history.length,2);
   await rpc('work_archive',{id:w.id});assert.equal((await rpc('work_list',{kind:'club_meeting'})).total,0);
   assert.equal((await rpc('work_list',{kind:'club_meeting',archived:true})).total,1);
   await rpc('work_archive',{id:w.id,restore:true});
   await login(4);await assert.rejects(rpc('work_detail',{id:w.id}),/Kayıt bulunamadı/);
  });
  await t.test('server pagination, metadata validation and chronological validation',async()=>{
   await login(4);
   for(let i=0;i<23;i++)await rpc('work_save',{kind:'pr_request',title:`Duyuru talebi ${i}`,body:'Kampüs',status:'open',data:{audience:'Öğrenciler'}});
   const first=await rpc('work_list',{kind:'pr_request',page:0}),second=await rpc('work_list',{kind:'pr_request',page:1});
   assert.equal(first.total,23);assert.equal(first.rows.length,20);assert.equal(second.rows.length,3);assert.equal(new Set([...first.rows,...second.rows].map(x=>x.id)).size,23);
   assert.equal((await rpc('work_list',{kind:'pr_request',q:'talebi 22'})).total,1);
   await assert.rejects(rpc('work_save',{kind:'pr_request',title:'Kötü alan',data:{is_admin:'true'}}),/Geçersiz kayıt alanı/);
   await assert.rejects(rpc('work_save',{kind:'pr_request',title:'Kötü bağlantı',data:{attachment_url:'javascript:alert(1)'}}),/Bağlantı/);
   await assert.rejects(rpc('work_save',{kind:'pr_request',title:'Tarih testi',starts_at:'2026-12-02',due_at:'2026-12-01',data:{}}),/Bitiş/);
   await assert.rejects(rpc('work_save',{kind:'pr_budget',title:'Karar testi',status:'approved',data:{}}),/Merkez/);
  });
  await t.test('candidate acceptance is idempotent and retains meeting history',async()=>{
   await login(8);const c=(await sql("insert into public.club_candidates(name,university) values('Bilim Topluluğu','Test Üniversitesi') returning id"))[0].id;
   const w=await rpc('work_save',{kind:'club_meeting',title:'Aday Meet',status:'completed',related_kind:'candidate',related_id:c,data:{outcome:'Kabul',next_step:'Tanışma'}});
   const a=await rpc('candidate_join',{id:c});assert.equal(a.club_id,c);assert.equal((await rpc('candidate_join',{id:c})).club_id,c);
   assert.equal((await sql('select count(*)::int n from public.club_contacts where source_work_id=$1',[w.id]))[0].n,1);
   assert.ok((await rpc('work_detail',{id:w.id})).history.length);
   await rpc('work_save',{kind:'club_event',title:'Kulübe özel buluşma',body:'Etkinlik açıklaması',status:'published',related_kind:'club',related_id:c,data:{}});
   await rpc('work_save',{kind:'center_message',title:'Kulübe mesaj',related_kind:'club',related_id:c,data:{}});
   assert.equal((await sql('select count(*)::int n from public.notifications where recipient_club_id=$1',[c]))[0].n,2);
  });
  await t.test('native detail fields, archival, revision history and permission boundaries',async()=>{
   await login(2);await rpc('post_request',{title:'Stüdyo testi',brief:'Brief'});const idp=(await sql("select id from public.social_posts where title='Stüdyo testi'"))[0].id;
   await rpc('record_save',{type:'post',id:idp,data:{instagram_text:'Platform metni',alt_text:'Öğrenciler',views:'15'}});
   assert.equal((await rpc('record_detail',{type:'post',id:idp})).details.data.views,'15');
   await rpc('post_save',{id:idp,title:'Stüdyo testi',body:'Yayın metni',platforms:['instagram']});await rpc('post_submit',{id:idp});
   await assert.rejects(rpc('record_save',{type:'post',id:idp,data:{instagram_text:'Onay atlatma'}}),/revizyon/);
   assert.ok((await rpc('record_detail',{type:'post',id:idp})).history.length>=3);
   await rpc('record_archive',{type:'post',id:idp});assert.equal((await rpc('record_list',{type:'post',archived:true,q:'Stüdyo'})).total,1);
   await rpc('record_archive',{type:'post',id:idp,restore:true});
   await login(4);assert.ok((await rpc('record_detail',{type:'post',id:idp})).history.length);await login(7);await assert.rejects(rpc('record_detail',{type:'post',id:idp}),/yetkin yok/);
  });
  await t.test('calendar feed and budgets respect roles; conversion is idempotent',async()=>{
   await login(4);const w=await rpc('work_save',{kind:'pr_request',title:'Dönüşecek talep',body:'Amaç',status:'approved',data:{}});
   const c=await rpc('work_convert',{id:w.id,target:'campaign'});assert.equal((await rpc('work_convert',{id:w.id,target:'campaign'})).id,c.id);
   await rpc('record_save',{type:'campaign',id:c.id,data:{starts_at:'2026-12-01T09:00:00Z',due_at:'2026-12-03T09:00:00Z',assignee:id(4),budget_amount:'2500'}});
   const feed=await rpc('workspace_feed',{from:'2026-12-01',to:'2026-12-31'});assert.ok(feed.rows.some(x=>x.id===c.id));assert.ok(feed.rows.every(x=>x.type!=='post'));
   await assert.rejects(rpc('work_save',{kind:'pr_budget',title:'Yetkisiz onay',status:'approved',data:{}}),/Merkez/);
   await login(1);const budget=await rpc('work_save',{kind:'pr_budget',title:'Onaylı bütçe',status:'approved',amount:2500,data:{currency:'TRY'}});assert.equal(budget.status,'approved');
  });
  await t.test('target unit can answer findings but cannot decide them',async()=>{
   await login(6);const finding=await rpc('work_save',{kind:'audit_finding',title:'PR düzeltmesi',status:'open',due_at:'2026-12-03',data:{target_unit:pr,severity:'high'}});
   await login(4);assert.ok((await rpc('corrections')).some(w=>w.id===finding.id));await rpc('correction_reply',{id:finding.id,body:'Düzeltildi',attachment_url:'https://example.com/evidence'});
   await assert.rejects(rpc('work_save',{...finding,status:'closed'}),/yetkin yok/);
   await login(2);await assert.rejects(rpc('work_detail',{id:finding.id}),/bulunamadı/);
   await login(6);assert.ok((await rpc('work_detail',{id:finding.id})).history.some(h=>h.body==='Düzeltildi'));
  });
  await t.test('documents are scoped and due reminders are deduplicated',async()=>{
   await login(2);await rpc('doc_add',{title:'Sosyal özel belge',url:'https://example.com/private'});
   await login(4);assert.ok(!(await sql('select public.uwr_docs() x'))[0].x.some(d=>d.title==='Sosyal özel belge'));
   await login(1);const doc=(await sql('select public.uwr_docs() x'))[0].x.find(d=>d.title==='Sosyal özel belge');await rpc('doc_update',{id:doc.id,title:'Güncel belge',url:'https://example.com/private'});
   await rpc('work_save',{kind:'pr_request',title:'Yaklaşan iş',due_at:new Date(Date.now()+86400000).toISOString(),data:{}});
   assert.ok((await rpc('due_refresh')).added>0);assert.equal((await rpc('due_refresh')).added,0);
  });
  await t.test('private attachments follow record visibility, writer identity and MFA',async()=>{
   await login(2);const w=await rpc('work_save',{kind:'center_message',title:'Özel ekli mesaj',data:{}});const path=`work/${w.id}/${id(2)}/test.pdf`;
   const can=async(write=false)=>(await sql('select public.unit_file_access($1,$2) ok',[path,write]))[0].ok;
   assert.equal(await can(true),true);await login(4);assert.equal(await can(),false);assert.equal(await can(true),false);
   await login(1);assert.equal(await can(),true);assert.equal(await can(true),false);
   await login(2,false);assert.equal(await can(),false);
  });
  await t.test('team announcements cannot target unrelated units; person messages are individually addressed',async()=>{
   await login(2);const ann=await rpc('ann_create',{title:'Ekip duyurusu',body:'Kendi ekibime',audience:[pr],attachment_url:'https://example.com/brief'});
   assert.deepEqual((await sql('select audience from public.unit_announcements where id=$1',[ann.id]))[0].audience,[social]);
   await login(4);assert.ok(!(await sql('select public.uwr_announcements() x'))[0].x.some(x=>x.id===ann.id));
   await sql('insert into auth.users values($1)',[id(10)]);await sql("insert into public.profiles(id,role,full_name,club_id) select $1,'club','Kulüp kişisi',id from public.clubs limit 1",[id(10)]);
   await rpc('work_save',{kind:'center_message',title:'Kişisel bildirim',related_kind:'person',related_id:id(10),data:{}});
   assert.equal((await sql('select count(*)::int n from public.notifications where recipient_user_id=$1',[id(10)]))[0].n,1);
   await db.exec('alter table public.notifications enable row level security;grant select on public.notifications,public.profiles to authenticated;grant usage on schema auth to authenticated');
   await login(10);await sql('set role authenticated');assert.equal((await sql('select count(*)::int n from public.notifications where recipient_user_id=$1',[id(10)]))[0].n,1);await sql('reset role');
   await login(4);await sql('set role authenticated');assert.equal((await sql('select count(*)::int n from public.notifications where recipient_user_id=$1',[id(10)]))[0].n,0);await sql('reset role');
  });
  await t.test('material approval requires a board member and retains the decision',async()=>{
   await login(4);const c=(await rpc('camp_save',{title:'Materyal kampanyası'})).id;
   const w=await rpc('work_save',{kind:'pr_material',title:'Afiş metni',body:'İçerik',status:'approval',related_kind:'campaign',related_id:c,data:{version:'1'}});
   await login(7);await assert.rejects(rpc('material_decide',{id:w.id,decision:'approved'}),/YK/);
   await login(2);assert.ok((await rpc('material_approvals')).some(x=>x.id===w.id));
   await rpc('material_decide',{id:w.id,decision:'rejected',note:'Tarih bilgisi eklenmeli'});
   await login(4);assert.ok((await rpc('work_detail',{id:w.id})).history.some(h=>h.body==='Tarih bilgisi eklenmeli'));
  });
  await t.test('task reassignment validates unit and archive prevents mutation',async()=>{
   await login(1);await assert.rejects(rpc('task_reassign',{id:task,assignee:id(4)}),/ilgili birim/);
   await rpc('task_reassign',{id:task,assignee:id(3)});await rpc('task_archive',{id:task});
   await assert.rejects(rpc('task_update',{id:task,title:'Arşivde değişiklik'}),/arşivden çıkar/);
   await rpc('task_archive',{id:task,restore:true});await rpc('task_update',{id:task,title:'Arşivden dönen görev'});
  });
  await t.test('club request routing, multi-club delivery and document relations persist',async()=>{
   await login(8);const clubs=await sql("insert into public.clubs(name,university) values('Birinci kulüp','Üniversite A'),('İkinci kulüp','Üniversite B') returning id");
   const event=await rpc('work_save',{kind:'club_event',title:'Ortak buluşma',body:'Davet',status:'published',related_kind:'club',related_id:clubs[0].id,data:{club_ids:clubs[1].id}});
   for(const c of clubs)assert.equal((await sql("select count(*)::int n from public.notifications where recipient_club_id=$1 and title='Ortak buluşma'",[c.id]))[0].n,1);
   await rpc('work_save',{...event,data:event.data});assert.equal((await sql("select count(*)::int n from public.notifications where title='Ortak buluşma'"))[0].n,2);
   const request=await rpc('work_save',{kind:'club_request',title:'PR yönlendirmesi',related_kind:'club',related_id:clubs[0].id,data:{target_unit:pr}});
   await login(4);assert.ok((await rpc('corrections')).some(x=>x.id===request.id));await rpc('correction_reply',{id:request.id,body:'İlgileniyoruz'});
   await assert.rejects(rpc('doc_add',{title:'Yanlış ilişki',url:'https://example.com',related_kind:'task',related_id:task}),/ilişkisi/);
   await login(1);await rpc('doc_add',{title:'Görev belgesi',url:'https://example.com',related_kind:'task',related_id:task});
   assert.equal((await sql("select related_id from public.unit_docs where title='Görev belgesi'"))[0].related_id,task);
   const msg=await rpc('work_save',{kind:'center_message',title:'Doğrudan bağlantı',data:{}});
   assert.ok((await sql('select public.uwr_notifications() x'))[0].x.some(n=>n.record_id===msg.id));
  });
  await t.test('audit members only see assigned workflow records without audit permission',async()=>{
   await login(6);const privatePlan=await rpc('work_save',{kind:'audit_plan',title:'Denetim ekibine özel plan',data:{}});
   const assigned=await rpc('work_save',{kind:'audit_plan',title:'Üyenin kontrolü',assignee:id(11),data:{}});
   await login(11);await assert.rejects(rpc('work_detail',{id:privatePlan.id}),/bulunamadı/);
   assert.equal((await rpc('work_detail',{id:assigned.id})).record.id,assigned.id);
   await assert.rejects(rpc('work_save',{...assigned,title:'Yetkisiz değiştirme'}),/yetkin yok/);
  });
  await t.test('workflow helpers stay private and schema replays without losing records',async()=>{
   assert.equal((await sql("select has_function_privilege('authenticated','public.uwa_work_detail(jsonb)','EXECUTE') as ok"))[0].ok,false);
   for(const name of ['20261107_unit_workspace_foundation','20261108_unit_workflows','20261109_unit_record_details','20261110_unit_private_files','20261111_unit_shared_integrity','20261112_unit_routing_and_documents'])await db.exec(migration(name));
   await login(4);assert.ok((await rpc('work_list',{kind:'pr_request'})).total>=23);
  });
  await t.test('migration replay preserves tasks and comments',async()=>{
   await db.exec(migration('20261107_unit_workspace_foundation'));assert.ok((await sql('select count(*)::int n from public.unit_task_history where task_id=$1',[task]))[0].n>=4);
  });
 } finally {await db.close();}
});
