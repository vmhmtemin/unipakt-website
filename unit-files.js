/* Private Supabase attachments; the stored link is stable and signed only on use. */
(()=>{'use strict';let C;
window.UniPaktFiles={async openPending(){const url=new URL(location.href),path=url.searchParams.get('unitFile');if(!path||!C||C.demo.enabled)return;url.searchParams.delete('unitFile');history.replaceState(null,'',url);try{location.assign(await C.storageSign(path));}catch(error){C.toast(error.message);}},install(context){C=context;
 document.addEventListener('change',async e=>{const input=e.target;if(!input.matches('[data-unit-upload]')||!input.files?.length)return;
 const file=input.files[0],status=input.parentElement.querySelector('[role="status"]');status.textContent='Yükleniyor…';input.disabled=true;
 try{if(file.size>10*1024*1024)throw new Error('En fazla 10 MB yüklenebilir.');
 const path=`${input.dataset.unitKind||'work'}/${input.dataset.unitUpload}/${C.me().id}/${crypto.randomUUID()}.${file.name.split('.').pop().replace(/[^a-z0-9]/gi,'').slice(0,10)||'bin'}`;
 if(C.demo.enabled)throw new Error('Dosya yükleme gerçek hesapla kullanılabilir; demoda bağlantı ekleyebilirsin.');
 await C.storageUpload(path,file);
 const url=new URL('/panel.html',location.origin);url.searchParams.set('unitFile',path);
 input.closest('form').elements[input.dataset.unitField||'extra_attachment_url'].value=url.href;status.textContent='Yüklendi. Bağlantıyı kaydetmek için formu kaydet.';
 }catch(error){status.textContent=error.message;}finally{input.disabled=false;}
 });
 document.addEventListener('click',async e=>{const a=e.target.closest('a[href]');if(!a)return;let url;try{url=new URL(a.href);}catch{return;}const path=url.searchParams.get('unitFile');if(!path||url.origin!==location.origin)return;e.preventDefault();try{const signed=await C.storageSign(path);window.open(signed,'_blank','noopener,noreferrer');}catch(error){C.toast(error.message);}});
}};
})();
