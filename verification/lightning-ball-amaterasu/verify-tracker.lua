-- Exercise the real tracker with synthetic SDK objects. No game process is called.
local autorun, original_path, prepared_path = arg[1], arg[2], arg[3]
package.path = autorun..'/?.lua;'..package.path
local time, checks, manager = 0, 0, nil
os.clock = function() return time end
local installed_hooks = {}
package.loaded['DragonCore.game.mathx'] = {}
package.loaded['DragonCore.game.hooks'] = {install=function(t,m,pre,post)
    installed_hooks[t..'.'..m]={pre=pre,post=post}
end}
package.loaded['DragonCore.game.enums'] = {value=function() return nil end}
package.loaded['DragonCore.game.hits'] = {effect_spec=function() return nil end}
sdk = {get_managed_singleton=function(name)
    assert(name=='app.ShellManager'); return manager
end, typeof=function(t) return t end}
local function check(ok, label)
    assert(ok,label); checks=checks+1; print('PASS: '..label)
end
local function part(address, hash, request)
    local p={address=address, valid=true, destroyed=0,
        ['<ShellParamId>k__BackingField']=hash,
        ['<RequestId>k__BackingField']=request}
    local transform={get_Valid=function() return p.valid end,
        get_Position=function() return {} end,get_Rotation=function() return {} end}
    local go={get_Transform=function() return transform end,
        call=function() return nil end,
        destroy=function() p.destroyed=p.destroyed+1; p.valid=false end}
    function p:get_address() return self.address end
    function p:get_Valid() return self.valid end
    function p:get_GameObject() return go end
    return p
end
local function setup(path, lifetime, cap, children, keep_alive)
    time=0
    local tracker=assert(loadfile(path))()
    local root,child=part(101,11,1),part(102,22,2)
    local dict={ContainsKey=function(_,key) return key==1 end,
        [1]={['<Shell>k__BackingField']=root}}
    manager={['<InstantiatedShellDict>k__BackingField']=dict,
        ShellList={_items=children and {[0]=child} or {},_size=children and 1 or 0}}
    local parameter={_ShellAdditionalParameter={_items=children and {
        [0]={_ShellParamIDHash=22}} or {}}}
    tracker.cap=cap
    tracker.track({req_id=1,node={lifetime=lifetime,keep_alive=keep_alive},
        actor={},param=parameter,udata={}})
    tracker.update()
    return tracker,root,child
end

do
    local tracker,root=setup(original_path,5,120)
    time=15; tracker.update()
    check(root.destroyed==0 and tracker.count()==1,
        'Original tracker reproduces a native shell persisting beyond lifetime 5')
    tracker.shutdown()
end
do
    local tracker,root,child=setup(prepared_path,5,120,true)
    time=4.99; tracker.update()
    check(root.destroyed==0 and child.destroyed==0,'Root and tracked child survive before five seconds')
    time=5.01; tracker.update()
    check(root.destroyed==1 and child.destroyed==1 and tracker.count()==0,
        'Explicit lifetime removes only this tracked root and its tracked child')
    tracker.update()
    check(root.destroyed==1 and child.destroyed==1,'Expired shells are not destroyed twice')
end
for _,lifetime in ipairs({0,false}) do
    local tracker,root=setup(prepared_path,lifetime or nil,120)
    time=15; tracker.update()
    check(root.destroyed==0,'Zero or omitted lifetime keeps native duration and global cap')
    time=120.01; tracker.update()
    check(root.destroyed==1,'Global cap still removes an untimed shell')
end
do
    local tracker,root=setup(prepared_path,20,3)
    time=3.01; tracker.update()
    check(root.destroyed==1,'Shorter global cap still wins')
end
do
    local tracker,root=setup(prepared_path,5,0)
    time=5.01; tracker.update()
    check(root.destroyed==1,'Explicit lifetime works when global cap is disabled')
end
do
    local tracker,root=setup(prepared_path,5,120,false,true)
    time=5.01; tracker.update()
    check(root.destroyed==1 and tracker.count()==0,'Keep-alive cannot exceed explicit lifetime')
end
do
    local tracker,root=setup(prepared_path,5,120)
    root.valid=false
    time=1; tracker.update()
    check(root.destroyed==0 and tracker.count()==0,'Natural early finish is preserved')
end
do
    local tracker,root=setup(prepared_path,nil,0)
    time=200; tracker.update()
    check(root.destroyed==0 and tracker.count()==1,'No lifetime and no global cap remains unlimited')
end
print(('Completed %d tracker checks. Native destruction still needs an in-game check.'):format(checks))
