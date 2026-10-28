import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import Scene, { TargetDamage } from './Scene';
import ActionList from '../sheets/ActionList';
const mocks=vi.hoisted(()=>({master:false,mutate:vi.fn(),targets:[] as any[],requests:[] as any[]}));
vi.mock('../../app',()=>({useApp:()=>({masterMode:mocks.master,cid:'1',sid:'1',user:{id:1},refresh:vi.fn(),notify:vi.fn()}),
 useData:(path:string)=>({data:path.startsWith('/scene/targets/')?{targets:mocks.targets,damage_types:{fire:'Огонь',cold:'Холод'}}:mocks.requests,isPending:false}),
 useAction:()=>({mutate:mocks.mutate,isPending:false,error:null})}));
afterEach(cleanup);
beforeEach(()=>{mocks.master=false;mocks.mutate.mockReset();mocks.requests=[];mocks.targets=[{id:1,name:'Стражник № 1',targetable:true,hp_current:19,hp_max:40,visible:true},{id:2,name:'Стражник № 2',targetable:true,hp_current:40,hp_max:40,visible:true}];});
it('players see identities without HP or management, even if a cached object contained health',()=>{
 render(<Scene characters={[]}/>);
 expect(screen.getByText('Стражник № 1')).toBeInTheDocument();
 expect(screen.queryByText('19/40')).not.toBeInTheDocument();
 expect(screen.queryByText('Настроить')).not.toBeInTheDocument();
 expect(screen.queryByText('Добавить из листа')).not.toBeInTheDocument();
});
it('applies independent save outcomes immediately without a master review',()=>{
 render(<TargetDamage event={{id:7,kind:'ability',payload:{damage_type:'fire',damage:{total:21},save:{ability:'dex',dc:15}}}}/>);
 fireEvent.click(screen.getByText('Применить к цели'));
 fireEvent.click(screen.getByLabelText('Стражник № 1'));fireEvent.click(screen.getByLabelText('Стражник № 2'));
 fireEvent.change(screen.getByLabelText('Спасбросок: Стражник № 1'),{target:{value:'failure'}});
 fireEvent.change(screen.getByLabelText('Спасбросок: Стражник № 2'),{target:{value:'success'}});
 fireEvent.click(screen.getByText('Нанести урон (2)'));
 expect(mocks.mutate.mock.calls[0][0].body).toEqual({source_event:7,part_index:0,targets:[1,2],outcomes:{'1':{save_outcome:'failure'},'2':{save_outcome:'success'}}});
 expect(screen.queryByText('19/40')).not.toBeInTheDocument();
});
it('an attack selects one target at a time',()=>{
 render(<TargetDamage event={{id:8,kind:'ability',payload:{damage:{total:8},roll:{total:18}}}}/>);
 fireEvent.click(screen.getByText('Применить к цели'));
 fireEvent.click(screen.getByLabelText('Стражник № 1'));fireEvent.click(screen.getByLabelText('Стражник № 2'));
 expect(screen.getByLabelText('Стражник № 1')).not.toBeChecked();
 expect(screen.getByLabelText('Стражник № 2')).toBeChecked();
});
it('master can add several NPC instances with type-specific resistance',()=>{
 mocks.master=true;
 render(<Scene characters={[{id:3,name:'Стражник',kind:'npc'}]}/>);
 fireEvent.click(screen.getByText('Добавить из листа'));
 fireEvent.change(screen.getByLabelText('Количество экземпляров'),{target:{value:'3'}});
 fireEvent.change(screen.getByLabelText('Огонь'),{target:{value:'resistance'}});
 fireEvent.click(screen.getByText('Добавить в сцену'));
 expect(mocks.mutate.mock.calls[0][0].body).toEqual({source:3,count:3,defenses:{fire:'resistance'}});
});
it('per-spell advantage is sent to the cast callback before rolling',()=>{
 mocks.master=true;const onUse=vi.fn();
 const spell={id:1,name:'Луч',kind:'spell',resolution:'attack',level:0,ability:'int',proficient:true,bonus:0,dice:'1d4',damage_type:'cold'};
 render(<ActionList kind="spell" items={[spell]} sheet={{slots:{},computed:{modifiers:{int:3},proficiency:2}}} characterId={1} onUse={onUse} busy={false} disabled={false} loading={false} error={null}/>);
 fireEvent.change(screen.getByLabelText('Режим атаки Луч'),{target:{value:'advantage'}});
 fireEvent.click(screen.getByText('Применить'));
 expect(onUse).toHaveBeenCalledWith(spell,0,false,'advantage');
});

it('master has no review button or pending approval section',()=>{
 mocks.master=true;mocks.requests=[{id:9,label:'Огонь',target_name:'Стражник № 1',requester_name:'Игрок',status:'applied'}];
 render(<Scene characters={[]}/>);
 expect(screen.queryByText('Рассмотреть')).not.toBeInTheDocument();
 expect(screen.queryByText('Ожидают применения')).not.toBeInTheDocument();
 expect(screen.getByText('Последние применения урона')).toBeInTheDocument();
});
it('requires a save outcome before applying and exposes no resistance control',()=>{
 render(<TargetDamage event={{id:7,kind:'ability',payload:{damage_type:'fire',damage:{total:21},save:{ability:'dex',dc:15}}}}/>);
 fireEvent.click(screen.getByText('Применить к цели'));fireEvent.click(screen.getByLabelText('Стражник № 1'));
 expect(screen.getByText('Нанести урон (1)')).toBeDisabled();
 expect(screen.queryByLabelText('Защита от этого урона')).not.toBeInTheDocument();
 fireEvent.change(screen.getByLabelText('Спасбросок: Стражник № 1'),{target:{value:'failure'}});
 expect(screen.getByText('Нанести урон (1)')).not.toBeDisabled();
});
