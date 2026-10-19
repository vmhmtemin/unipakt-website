-- Applied to production on 2026-10-19.
-- Seven club categories replace the old four (Yazılım, Tasarım, Girişim, Eğlence).
update public.clubs set category = case
  when name = 'GDG on Campus'               then 'Yazılım & Teknoloji'
  when name = 'Endüstri ve Kalite Kulübü'   then 'Girişim & Kariyer'
  when name = 'Genç Kalite Kulübü'          then 'Girişim & Kariyer'
  when name = 'Kariyer Ve Gelişim Kulübü'   then 'Girişim & Kariyer'
  when name = 'Sosyal Sorumluluk Kulübü'    then 'Sosyal Sorumluluk'
  when name = 'Dans Kulübü'                 then 'Sanat & Kültür'
  when name = 'Gastrozone'                  then 'Yaşam & Hobi'
  when category = 'Yazılım'                 then 'Yazılım & Teknoloji'
  when category = 'Tasarım'                 then 'Tasarım & Medya'
  when category = 'Girişim'                 then 'Girişim & Kariyer'
  when category = 'Eğlence'                 then 'Yaşam & Hobi'
  else category
end;
