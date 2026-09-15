using System;
using System.Drawing;
using System.Windows.Forms;
namespace WD1Kit {
    public static class Theme {
        public static Color Bg=Color.FromArgb(12,21,35), Card=Color.FromArgb(24,37,56), Text=Color.FromArgb(232,240,248), Muted=Color.FromArgb(166,183,201), Accent=Color.FromArgb(68,211,182);
        public static void Form(Form f,string title) { f.Text=title; f.BackColor=Bg; f.ForeColor=Text; f.Font=new Font("Microsoft YaHei UI",10); f.StartPosition=FormStartPosition.CenterScreen; f.Size=new Size(1040,790); f.MinimumSize=new Size(900,650); f.AutoScaleMode=AutoScaleMode.Dpi; f.Shown+=(s,e)=>{var a=Screen.FromControl(f).WorkingArea;int w=Math.Max(400,a.Width-32),h=Math.Max(400,a.Height-32);f.MinimumSize=new Size(Math.Min(f.MinimumSize.Width,w),Math.Min(f.MinimumSize.Height,h));f.Size=new Size(Math.Min(f.Width,w),Math.Min(f.Height,h));f.Location=new Point(a.Left+(a.Width-f.Width)/2,a.Top+(a.Height-f.Height)/2);}; }
        public static Label Label(string text,bool heading=false) {return new Label {Text=text,AutoSize=true,ForeColor=heading?Text:Muted,Font=new Font("Microsoft YaHei UI",heading?15:10,heading?FontStyle.Bold:FontStyle.Regular),MaximumSize=new Size(900,0),Margin=new Padding(4,8,4,8)};}
        public static Button Button(string text,EventHandler click,bool primary=false) {
            var b=new Button {Text=text,AutoSize=true,MinimumSize=new Size(145,38),FlatStyle=FlatStyle.Flat,BackColor=primary?Accent:Card,ForeColor=primary?Bg:Text,Margin=new Padding(4,5,10,5),Padding=new Padding(8,2,8,2),Cursor=Cursors.Hand};
            b.FlatAppearance.BorderColor=Color.FromArgb(55,76,100); b.Click+=click; return b;
        }
        public static FlowLayoutPanel Flow(bool vertical=false) {return new FlowLayoutPanel {AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,FlowDirection=vertical?FlowDirection.TopDown:FlowDirection.LeftToRight,WrapContents=!vertical,Dock=DockStyle.Top,Padding=new Padding(8),BackColor=Bg};}
        public static Panel Header(string subtitle) {
            var p=new Panel {Dock=DockStyle.Top,Height=100,BackColor=Card,Padding=new Padding(22,10,22,8)};
            var a=Label("WD1  /  中文单机工具箱",true);a.Location=new Point(22,12);
            var b=Label(subtitle);b.Location=new Point(22,51); p.Controls.Add(a);p.Controls.Add(b);return p;
        }
        public static TextBox TextBox(bool multi=false) {return new TextBox {Width=730,Height=multi?210:30,Multiline=multi,ReadOnly=multi,ScrollBars=multi?ScrollBars.Vertical:ScrollBars.None,BackColor=Card,ForeColor=Text,BorderStyle=BorderStyle.FixedSingle,Margin=new Padding(4,4,4,4)};}
    }
}
