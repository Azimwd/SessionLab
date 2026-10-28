import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Campaigns from './Campaigns';
const mocks=vi.hoisted(()=>({mutate:vi.fn(),select:vi.fn(),user:1}));
vi.mock('../app',()=>({useApp:()=>({user:{id:mocks.user,account_role:'dm'},cid:'7',campaigns:[{id:7,name:'Приключение',owner:1,role:'dm'}],selectCampaign:mocks.select}),useAction:()=>({mutate:mocks.mutate,reset:vi.fn(),isPending:false,error:null})}));
afterEach(cleanup);
beforeEach(()=>{mocks.user=1;mocks.mutate.mockReset();mocks.select.mockReset();});
it('requires the exact name and only sends DELETE on explicit confirmation',()=>{
 render(<MemoryRouter><Campaigns/></MemoryRouter>);
 fireEvent.click(screen.getByRole('button',{name:'Удалить кампанию «Приключение»'}));
 const confirm=screen.getByRole('button',{name:'Удалить кампанию'});
 expect(confirm).toBeDisabled();expect(mocks.mutate).not.toHaveBeenCalled();
 fireEvent.change(screen.getByLabelText('Введите название кампании для подтверждения'),{target:{value:'Приключение'}});
 expect(confirm).toBeEnabled();fireEvent.click(confirm);
 expect(mocks.mutate.mock.calls[0][0]).toEqual({path:'/campaigns/7/',method:'DELETE',body:{confirm_name:'Приключение'}});
 mocks.mutate.mock.calls[0][1].onSuccess();expect(mocks.select).toHaveBeenCalledWith('');
});
it('a co-master cannot see the deletion button',()=>{
 mocks.user=2;render(<MemoryRouter><Campaigns/></MemoryRouter>);
 expect(screen.queryByRole('button',{name:/Удалить/})).not.toBeInTheDocument();
});
it('cancelling never deletes the campaign',()=>{
 render(<MemoryRouter><Campaigns/></MemoryRouter>);
 fireEvent.click(screen.getByRole('button',{name:'Удалить кампанию «Приключение»'}));
 fireEvent.click(screen.getByRole('button',{name:'Отмена'}));
 expect(screen.queryByRole('dialog')).not.toBeInTheDocument();expect(mocks.mutate).not.toHaveBeenCalled();
});
