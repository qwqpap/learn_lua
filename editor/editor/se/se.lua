--======================================
--Thlib se
--======================================

----------------------------------------
--自带的音效

local sounds={
	'alert','astralup','bonus','bonus2','boon00','boon01','cancel00','cardget','cat00','cat01','ch00','ch01','ch02','don00',
	'damage00','damage01','enep00','enep01','enep02','extend','fault','graze','gun00',
	'hint00','invalid','item00','kira00','kira01','kira02','lazer00','lazer01','lazer02',
	'msl','msl2','nep00','ok00','option','pause','pldead00','plst00','power0','power1',
	'powerup','select00','slash','tan00','tan01','tan02','timeout','timeout2',
	'warpl','warpr','water','explode','nice','nodamage','power02',
	'lgods1','lgods2','lgods3','lgods4','lgodsget','big','wolf','noise','pin00',
	'powerup1',
	'old_cat00','old_enep00','old_extend','old_gun00','old_kira00','old_kira01',
	'old_lazer01','old_nep00','old_pldead00','old_power0','old_power1','old_powerup',
	'hyz_charge00','hyz_charge01b','hyz_chargeup','hyz_eterase','hyz_exattack',
	'hyz_gosp','hyz_life1','hyz_playerdead','hyz_timestop0','hyz_warning',
	'bonus3','border','changeitem','down','extend2','focusfix','focusfix2','focusin',
	'heal','ice','ice2','item01','ophide','opshow',
}

for _,v in pairs(sounds) do
	LoadSound(v,'se_'..v..'.wav')
end
