using System;
using System.Linq;
using System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Runtime.InteropServices;
namespace WD1Kit.Native {
 public sealed class NativeForm:Form {
  readonly string game;readonly BackupInfo backup;readonly LocalStorage store;Engine engine;ScanDiagnostic lastScan;bool updating,busy;DateTime permitUntil=DateTime.MinValue;
  Timer timer=new Timer{Interval=120};ListView list=new ListView{Dock=DockStyle.Fill,CheckBoxes=true,FullRowSelect=true,View=View.Details,BackColor=Theme.Card,ForeColor=Theme.Text,HideSelection=false};
  Label status=Theme.Label("先做只读指纹 / AOB 扫描。尚未连接，不会自动启用任何功能。");Label detail=Theme.Label("选择一项查看独立范围、原始数值和限制。");
  TextBox search=Theme.TextBox();ComboBox scope=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Width=200};NumericUpDown value=new NumericUpDown{Minimum=-2000000000,Maximum=2000000000,Width=165,ThousandsSeparator=true};
  CheckBox offline=new CheckBox{Text="我确认仅单机、不联网，并将切换活动前先停止全部",AutoSize=true,ForeColor=Theme.Text,Margin=new Padding(6,8,5,8)};
  readonly string[] scopes={"freeroam","vehicle","spider","madness","hacking","drinking","cashrun","nvzn","alone","poker"};
  HashSet<string> favorites=new HashSet<string>();CheckBox onlyFavorites=new CheckBox{Text="仅收藏",AutoSize=true,ForeColor=Theme.Text};Dictionary<int,string> hotkeys=new Dictionary<int,string>();int nextKey=500;ComboBox keys=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Width=80};
  [DllImport("user32.dll",SetLastError=true)]static extern bool RegisterHotKey(IntPtr h,int id,uint modifiers,uint key);
  [DllImport("user32.dll")]static extern bool UnregisterHotKey(IntPtr h,int id);
  public NativeForm(string game,LocalStorage store,BackupInfo backup){
   this.game=game;this.backup=backup;this.store=store;try{var f=System.IO.Path.Combine(store.Root,"native-favorites.json");if(File.Exists(f))favorites=new HashSet<string>(Files.Read<string[]>(f).Where(id=>Contracts.Options.Any(o=>o.Id==id)));}catch{}Theme.Form(this,"WD1 游戏内参数 · 独立开关 / 增加 / 减少 · v0.3.3 Alpha");Width=1170;
   var head=Theme.Flow(true);head.Controls.Add(Theme.Label("游戏内参数控制 · 原生候选引擎",true));
   head.Controls.Add(Theme.Label("这里直接操作你选定游戏进程的候选代码/数值，不需要其他 CE 程序。未在你的机器实测；捕获对象不等于自动识别活动或玩家，请先备份。"));
   var bar=Theme.Flow();bar.Controls.Add(Theme.Button("只读连接 / 扫描",(s,e)=>Connect(),true));bar.Controls.Add(Theme.Button("停止全部",(s,e)=>Run(()=>{if(engine!=null)engine.StopAll();RefreshRows();})));bar.Controls.Add(Theme.Button("恢复代码并断开",(s,e)=>Run(()=>Disconnect())));bar.Controls.Add(Theme.Button("导出诊断（失败也可）",(s,e)=>Export()));head.Controls.Add(bar);
   var modes=Theme.Flow();scope.Items.AddRange(new object[]{"本体 / Bad Blood 自由探索","驾车（先确认捕获对象）","蜘蛛坦克","疯狂 Madness","黑客小游戏","饮酒小游戏","Cash Run（尚待独立绑定）","NVZN（尚待独立绑定）","孤独 Alone（尚待独立绑定）","扑克 1–4（尚待独立绑定）"});scope.SelectedIndex=0;
   scope.SelectedIndexChanged+=(s,e)=>{if(updating||engine==null)return;try{engine.ChangeScope(scopes[scope.SelectedIndex]);RefreshRows();}catch(Exception ex){updating=true;scope.SelectedIndex=Array.IndexOf(scopes,engine.Scope);updating=false;MessageBox.Show(ex.Message,"活动切换未完成，保持原范围");}};modes.Controls.Add(scope);modes.Controls.Add(offline);head.Controls.Add(modes);
   search.Width=380;search.TextChanged+=(s,e)=>RefreshRows();var filter=Theme.Flow();filter.Controls.Add(Theme.Label("筛选："));filter.Controls.Add(search);onlyFavorites.CheckedChanged+=(s,e)=>RefreshRows();filter.Controls.Add(onlyFavorites);filter.Controls.Add(Theme.Button("收藏 / 取消所选",(s,e)=>Run(()=>{var o=SelectedOption();if(!favorites.Add(o.Id))favorites.Remove(o.Id);Files.Write(Path.Combine(store.Root,"native-favorites.json"),favorites.ToArray());RefreshRows();})));head.Controls.Add(filter);head.Controls.Add(status);
   list.Columns.Add("独立功能 / 增减操作",275);list.Columns.Add("类别",115);list.Columns.Add("范围",100);list.Columns.Add("当前状态（不是游戏认证）",500);
   list.ItemCheck+=OnCheck;list.SelectedIndexChanged+=(s,e)=>Selected();
   var bottom=Theme.Flow(true);var actions=Theme.Flow();actions.Controls.Add(Theme.Button("捕获所选对象",(s,e)=>Run(()=>{Need();var id=SelectedOption().Id;engine.Observe(id);status.Text="捕获已请求；请看下方明确状态及执行次数，不需要抢2秒窗口。";RefreshDetail();})));
   actions.Controls.Add(value);actions.Controls.Add(Theme.Button("排队一次增减",(s,e)=>Run(()=>{Need();var o=SelectedOption();if(!(o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_")))throw new IOException("此项是独立开关，请勾选启用；增减项用这个按钮。");if(MessageBox.Show("确定排队一次："+o.Name+" / 增减量 "+value.Value+"？\n不会立即使用旧对象写入；需同一对象的新心跳，30秒无刷新自动取消。","一次性确认",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)==DialogResult.Yes){engine.QueueOnce(o.Id,(double)value.Value);status.Text="已排队，尚未写入。切回游戏触发刷新，或点取消排队；30秒超时不执行。";RefreshRows();}})));
   actions.Controls.Add(Theme.Button("取消排队",(s,e)=>Run(()=>{Need();engine.CancelQueued();RefreshStates();status.Text="一次性排队已取消。";})));
   foreach(var k in Enumerable.Range(1,12))keys.Items.Add("F"+k);keys.SelectedIndex=0;actions.Controls.Add(keys);actions.Controls.Add(Theme.Button("绑定 Ctrl+Alt+此键",(s,e)=>BindKey()));bottom.Controls.Add(actions);bottom.Controls.Add(detail);
   Controls.Add(list);Controls.Add(bottom);bottom.Dock=DockStyle.Bottom;Controls.Add(head);
   timer.Tick+=(s,e)=>{if(engine==null||busy)return;try{engine.Tick();RefreshStates();}catch(Exception ex){status.Text="保护停止："+ex.Message;}};timer.Start();
   FormClosing+=(s,e)=>{if(busy){e.Cancel=true;return;}try{Disconnect();}catch(Exception ex){e.Cancel=true;MessageBox.Show(ex.Message+"\n请稍后再试；若无法恢复，请先正常退出游戏再关闭工具。","尚未安全断开");}};
   FormClosed+=(s,e)=>{timer.Stop();foreach(var id in hotkeys.Keys)UnregisterHotKey(Handle,id);};RefreshRows();
  }
  bool Authorized(){return offline.Checked&&DateTime.UtcNow<=permitUntil&&backup!=null&&File.Exists(backup.ManifestPath);}
  void Need(){if(engine==null)throw new IOException("请先连接。");}
  Option SelectedOption(){if(list.SelectedItems.Count!=1)throw new IOException("先选中一项。");return (Option)list.SelectedItems[0].Tag;}
  async void Connect(){if(busy)return;try{Disconnect();}catch(Exception ex){MessageBox.Show(ex.Message);return;}
   busy=true;UseWaitCursor=true;lastScan=new ScanDiagnostic();try{
    lastScan.Stage="BACKUP_METADATA";if(backup!=null){store.Verify(backup.ManifestPath);permitUntil=DateTime.Parse(backup.Manifest.CreatedUtc,null,System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime().AddHours(2);}else permitUntil=DateTime.MinValue;
    engine=await Task.Run(()=>{WinMemory pending=null;try{pending=new WinMemory(game,lastScan);return new Engine(pending,Authorized);}catch(Exception ex){lastScan.Failure(ex);if(pending!=null)pending.Dispose();throw;}});
    status.Text=lastScan.Complete?"只读分块扫描完成。唯一签名不是功能认证，先导出诊断。":"只读扫描不完整，全部捕获/修改保持锁定。请点“导出诊断（失败也可）”。";RefreshRows();
   }catch(Exception ex){lastScan.Failure(ex);status.Text="连接失败："+ex.Message+"；可导出诊断。";MessageBox.Show(ex.Message+"\n\n不用重选路径或更换站位。现在可点“导出诊断（失败也可）”。","未连接 / 诊断已保留");}finally{busy=false;UseWaitCursor=false;}
  }
  void Run(Action action){if(busy)return;try{action();}catch(Exception ex){status.Text="未执行 / 未完成："+ex.Message;MessageBox.Show(ex.Message,"WD1 参数控制",MessageBoxButtons.OK,MessageBoxIcon.Warning);}}
  void Disconnect(){if(engine!=null){engine.Disconnect();engine=null;}status.Text="已断开，未自动恢复任何保存的开关。";RefreshRows();}
  void OnCheck(object sender,ItemCheckEventArgs e){if(updating)return;var o=(Option)list.Items[e.Index].Tag;if(o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_")){e.NewValue=e.CurrentValue;return;}
   try{Need();if(e.NewValue==CheckState.Checked){if(o.Kind.Contains("patch")||o.Kind=="return_zero"){
     if(MessageBox.Show("启用独立候选："+o.Name+"\n"+(o.Note??"")+"\n只接受唯一匹配的原始指令；仍可能与任务或宿主冲突。继续？","启用代码开关",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)!=DialogResult.Yes){e.NewValue=e.CurrentValue;return;}}
     double? target=(list.SelectedItems.Count==1&&list.SelectedItems[0]==list.Items[e.Index])?(double?)value.Value:null;engine.Enable(o.Id,target);
    }else engine.Disable(o.Id);
   }catch(Exception ex){e.NewValue=e.CurrentValue;status.Text="未改变开关："+ex.Message;MessageBox.Show(ex.Message,"开关没有成功执行");}
  }
  void Selected(){if(list.SelectedItems.Count!=1)return;var o=(Option)list.SelectedItems[0].Tag;value.Value=(decimal)Math.Max(-2000000000,Math.Min(2000000000,o.Value));
   value.Enabled=!(o.Kind.Contains("patch")||o.Kind=="return_zero"||o.Kind=="freeze_f32"||o.Kind=="capacity_f32"||o.Kind.StartsWith("once_")||new[]{"rep_good","rep_bad","police_detection","heat_hold"}.Contains(o.Id));
   RefreshDetail();
  }
  void RefreshDetail(){
   if(list.SelectedItems.Count!=1)return;var o=(Option)list.SelectedItems[0].Tag;
   if(engine==null){detail.Text=o.Name+"：尚未连接。";return;}
   try{var info=engine.Preview(o.Id);string number=info.Value.HasValue?info.Value.Value.ToString("0.###"):"无有效样本";
    detail.Text=o.Name+" ｜ "+(info.CachedOnly?"暂停/过期缓存值":"最近原始样本")+"："+number+"\n"+
     "["+info.Code+"] 捕获次数="+info.HitCount+"；稳定采样="+info.StableSamples+"；距刷新="+(info.SecondsSinceHit.HasValue?info.SecondsSinceHit.Value.ToString("0.0")+"秒":"从未")+"\n"+
     info.Explanation+"\n"+(o.Note??"样本符合范围不等于对象身份已验证；先核对游戏显示值。")+"\n无限维持与一次性增加独立；超过2秒只允许查看缓存/预置，真正写入仍等新鲜同一对象。";
   }catch(Exception ex){detail.Text="捕获诊断不可用："+ex.Message;}
  }
  void RefreshRows(){if(list==null)return;string selected=list.SelectedItems.Count==1?((Option)list.SelectedItems[0].Tag).Id:null;updating=true;list.BeginUpdate();list.Items.Clear();
   foreach(var o in Contracts.Options.Where(x=>(!onlyFavorites.Checked||favorites.Contains(x.Id))&&(string.IsNullOrWhiteSpace(search.Text)||(x.Name+" "+x.Group+" "+x.Scope).IndexOf(search.Text,StringComparison.OrdinalIgnoreCase)>=0))){
    var item=new ListViewItem((favorites.Contains(o.Id)?"★ ":"")+((o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_"))?"[单次] ":"")+o.Name){Tag=o,Checked=engine!=null&&engine.Enabled(o.Id)};item.SubItems.Add(o.Group);item.SubItems.Add(o.Scope);item.SubItems.Add(RowStatus(o));list.Items.Add(item);if(o.Id==selected)item.Selected=true;
   }list.EndUpdate();updating=false;
  }
  string RowStatus(Option o){if(engine==null)return "未连接 / 未验证";if(engine.Enabled(o.Id))return engine.State(o.Id);if(engine.HasCaptureFor(o.Id))return engine.CaptureSummary(o.Id)+" ｜ "+engine.State(o.Id);if(engine.Messages.ContainsKey(o.Id))return engine.State(o.Id);return string.Join("；",o.Site.Split(new[] { ',' }, StringSplitOptions.None).Select(s=>engine.Sites[s].Status+" ("+s+")"));}
  void RefreshStates(){updating=true;foreach(ListViewItem item in list.Items){var o=(Option)item.Tag;item.Checked=engine!=null&&engine.Enabled(o.Id);item.SubItems[3].Text=RowStatus(o);}updating=false;RefreshDetail();}
  void BindKey(){Run(()=>{var o=SelectedOption();if(Environment.OSVersion.Platform!=PlatformID.Win32NT)throw new IOException("快捷键只在 Windows 注册。");uint key=(uint)((int)Keys.F1+keys.SelectedIndex);int id=nextKey++;
    if(!RegisterHotKey(Handle,id,0x4003,key))throw new IOException("组合键被其他软件占用。");hotkeys[id]=o.Id;status.Text="已绑定 Ctrl+Alt+"+keys.SelectedItem+" → "+o.Name+"。重启工具不自动注册或启用。";});}
  protected override void WndProc(ref Message m){if(m.Msg==0x0312){string id;if(hotkeys.TryGetValue(m.WParam.ToInt32(),out id))Run(()=>{Need();var o=Contracts.Options.Single(v=>v.Id==id);if(o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_")){if(MessageBox.Show("确认排队一次："+o.Name+"（默认量 "+o.Value+"）？\n等同一对象新心跳才执行；30秒无刷新取消。","快捷键操作确认",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)==DialogResult.Yes)engine.QueueOnce(id);RefreshStates();return;}if(engine.Enabled(id))engine.Disable(id);else engine.Enable(id);RefreshStates();});}base.WndProc(ref m);}
  public static object ExportPayload(Engine current,ScanDiagnostic diagnostic){
   if(current==null&&diagnostic==null)throw new IOException("尚未尝试连接。");
   return new {version="0.3.3-alpha",connected=current!=null,scan=diagnostic,candidates=current==null?null:current.Report()};
  }
  void Export(){Run(()=>{if(engine==null&&lastScan==null)throw new IOException("请先尝试一次只读连接，失败也会保留诊断。");using(var d=new SaveFileDialog{Filter="JSON|*.json",FileName="WD1-Native-Probe.json"})if(d.ShowDialog(this)==DialogResult.OK){if(Files.Under(d.FileName,game)||Files.Under(d.FileName,store.Root))throw new IOException("请另存桌面/下载目录，不能覆盖游戏或备份。");Files.Write(d.FileName,ExportPayload(engine,lastScan));status.Text="已导出扫描与捕获诊断（次数/稳定性/时间/原始资源样本）；无地址、路径、账号或内存转储。";}});}
 }
}
