using System.Text.Json;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using W = DocumentFormat.OpenXml.Wordprocessing;
using A = DocumentFormat.OpenXml.Drawing;
using DW = DocumentFormat.OpenXml.Drawing.Wordprocessing;
using PIC = DocumentFormat.OpenXml.Drawing.Pictures;

if (args.Length != 2) throw new ArgumentException("Usage: ArchitectureDocx content.json output.docx");
var blocks = JsonDocument.Parse(File.ReadAllText(args[0])).RootElement;
using (var doc = WordprocessingDocument.Create(args[1], WordprocessingDocumentType.Document)) {
 var main = doc.AddMainDocumentPart(); var body = new W.Body(); main.Document = new W.Document(body);
 var styles = new W.Styles(); main.AddNewPart<StyleDefinitionsPart>().Styles = styles;
 styles.Append(new W.DocDefaults(new W.RunPropertiesDefault(new W.RunPropertiesBaseStyle(
  new W.RunFonts { Ascii="Calibri", HighAnsi="Calibri", EastAsia="SimSun" },new W.FontSize { Val="22" },new W.Languages { Val="en-US", EastAsia="zh-CN" })),
  new W.ParagraphPropertiesDefault(new W.ParagraphPropertiesBaseStyle(new W.SpacingBetweenLines { Line="276", LineRule=W.LineSpacingRuleValues.Auto, After="160" }))));
 styles.Append(new W.Style(new W.StyleName { Val="Normal" }) { Type=W.StyleValues.Paragraph, StyleId="Normal", Default=true });
 for(int level=1;level<=3;level++) {
  styles.Append(new W.Style(new W.StyleName { Val=$"heading {level}" },new W.BasedOn { Val="Normal" },new W.NextParagraphStyle { Val="Normal" },
   new W.StyleParagraphProperties(new W.KeepNext(), new W.SpacingBetweenLines { Before=level==1?"480":level==2?"360":"240",After="120" },new W.OutlineLevel { Val=level-1 }),
   new W.StyleRunProperties(new W.RunFonts { Ascii="Calibri",HighAnsi="Calibri",EastAsia="Microsoft YaHei" },new W.Bold(),new W.Color { Val="1F3864" },new W.FontSize { Val=level==1?"40":level==2?"32":"26" })) { Type=W.StyleValues.Paragraph,StyleId=$"Heading{level}" });
 }
 styles.Append(new W.Style(new W.StyleName { Val="Title" },new W.BasedOn { Val="Normal" },new W.StyleParagraphProperties(new W.KeepNext(),new W.SpacingBetweenLines { After="240" }),new W.StyleRunProperties(new W.Bold(),new W.Color { Val="1F3864" },new W.FontSize { Val="44" })) { Type=W.StyleValues.Paragraph,StyleId="Title" });
 styles.Append(new W.Style(new W.StyleName { Val="Code" },new W.BasedOn { Val="Normal" },new W.StyleParagraphProperties(new W.SpacingBetweenLines { After="40",Line="240",LineRule=W.LineSpacingRuleValues.Auto }),new W.StyleRunProperties(new W.RunFonts { Ascii="Consolas",HighAnsi="Consolas",EastAsia="SimSun" },new W.FontSize { Val="18" })) { Type=W.StyleValues.Paragraph,StyleId="Code" });
 var header=main.AddNewPart<HeaderPart>(); header.Header=new W.Header(Para("COFDM 基带整体链路架构  ·  2026-09-28",null,true));
 var footer=main.AddNewPart<FooterPart>(); var fp=Para("",null,true); fp.Append(new W.SimpleField(new W.Run(new W.Text("1"))) { Instruction="PAGE" });footer.Footer=new W.Footer(fp);
 uint pictureId=1;
 foreach(var b in blocks.EnumerateArray()) {
  string kind=b.GetProperty("kind").GetString()!;
  if(kind=="heading") {int l=b.GetProperty("level").GetInt32();body.Append(Para(b.GetProperty("text").GetString()!,l==1?"Title":$"Heading{l-1}"));}
  else if(kind=="paragraph" || kind=="code") body.Append(Para(b.GetProperty("text").GetString()!,kind=="code"?"Code":null));
  else if(kind=="table") {
   var rows=b.GetProperty("rows").EnumerateArray().ToArray(); int count=rows[0].GetArrayLength(); int width=9026/count;
   var table=new W.Table(); var props=new W.TableProperties(new W.TableWidth { Width="9026",Type=W.TableWidthUnitValues.Dxa },
    new W.TableBorders(new W.TopBorder { Val=W.BorderValues.Single,Size=4,Color="D6DEE8" },new W.BottomBorder { Val=W.BorderValues.Single,Size=4,Color="D6DEE8" },new W.InsideHorizontalBorder { Val=W.BorderValues.Single,Size=4,Color="D6DEE8" }),
    new W.TableLayout { Type=W.TableLayoutValues.Fixed },new W.TableCellMarginDefault(new W.TopMargin { Width="72",Type=W.TableWidthUnitValues.Dxa },new W.TableCellLeftMargin { Width=108,Type=W.TableWidthValues.Dxa },new W.BottomMargin { Width="72",Type=W.TableWidthUnitValues.Dxa },new W.TableCellRightMargin { Width=108,Type=W.TableWidthValues.Dxa }));
   table.Append(props); var grid=new W.TableGrid();for(int j=0;j<count;j++)grid.Append(new W.GridColumn { Width=width.ToString() });table.Append(grid);
   for(int i=0;i<rows.Length;i++) {var row=new W.TableRow();var rp=new W.TableRowProperties(new W.CantSplit());if(i==0)rp.Append(new W.TableHeader());row.Append(rp);
    foreach(var v in rows[i].EnumerateArray()) {
     var cell=new W.TableCell();cell.Append(new W.TableCellProperties(new W.TableCellWidth { Width=width.ToString(),Type=W.TableWidthUnitValues.Dxa },new W.Shading { Fill=i==0?"E7EEF7":i%2==0?"F5F7FA":"FFFFFF",Val=W.ShadingPatternValues.Clear }));
     var p=Para(v.GetString()!);p.ParagraphProperties!.SpacingBetweenLines=new W.SpacingBetweenLines { After="40",Line="240",LineRule=W.LineSpacingRuleValues.Auto };
     foreach(var run in p.Elements<W.Run>()) { run.RunProperties=new W.RunProperties(new W.FontSize { Val="20" });if(i==0)run.RunProperties.PrependChild(new W.Bold()); }
     cell.Append(p);row.Append(cell);
    } table.Append(row);
   }body.Append(table);
  }
  else if(kind=="image") {
   var path=b.GetProperty("path").GetString()!;long cx=5486400,cy=(long)(cx*b.GetProperty("height").GetDouble()/b.GetProperty("width").GetDouble());
   if(cy>5181600){cx=(long)(cx*5181600.0/cy);cy=5181600;}
   var part=main.AddImagePart(ImagePartType.Png);using(var stream=File.OpenRead(path))part.FeedData(stream);
   var picture=new PIC.Picture(new PIC.NonVisualPictureProperties(new PIC.NonVisualDrawingProperties { Id=pictureId,Name=Path.GetFileName(path) },new PIC.NonVisualPictureDrawingProperties()),
    new PIC.BlipFill(new A.Blip { Embed=main.GetIdOfPart(part) },new A.Stretch(new A.FillRectangle())),new PIC.ShapeProperties(new A.Transform2D(new A.Offset { X=0,Y=0 },new A.Extents { Cx=cx,Cy=cy }),new A.PresetGeometry(new A.AdjustValueList()) { Preset=A.ShapeTypeValues.Rectangle }));
   var inline=new DW.Inline(new DW.Extent { Cx=cx,Cy=cy },new DW.EffectExtent { LeftEdge=0,TopEdge=0,RightEdge=0,BottomEdge=0 },new DW.DocProperties { Id=pictureId++,Name=b.GetProperty("alt").GetString()! },new DW.NonVisualGraphicFrameDrawingProperties(new A.GraphicFrameLocks { NoChangeAspect=true }),new A.Graphic(new A.GraphicData(picture) { Uri="http://schemas.openxmlformats.org/drawingml/2006/picture" }));
   var para=new W.Paragraph(new W.ParagraphProperties(new W.KeepNext(),new W.Justification { Val=W.JustificationValues.Center }),new W.Run(new W.Drawing(inline)));body.Append(para);body.Append(Para(b.GetProperty("alt").GetString()!,null,true));
  }
 }
 body.Append(new W.SectionProperties(new W.HeaderReference { Type=W.HeaderFooterValues.Default,Id=main.GetIdOfPart(header) },new W.FooterReference { Type=W.HeaderFooterValues.Default,Id=main.GetIdOfPart(footer) },new W.PageSize { Width=11906,Height=16838 },new W.PageMargin { Top=1440,Right=1440,Bottom=1440,Left=1440,Header=720,Footer=720,Gutter=0 }));
 doc.PackageProperties.Title="COFDM 基带整体链路架构";doc.PackageProperties.Subject="当前MATLAB收发链与模块职责";main.Document.Save();
 var errors=new OpenXmlValidator().Validate(doc).ToList();foreach(var e in errors)Console.Error.WriteLine($"{e.Path?.XPath}: {e.Description}");if(errors.Count>0)throw new Exception($"OpenXML errors: {errors.Count}");
 Console.WriteLine($"Created {args[1]}; OpenXML validation: 0 errors.");
}
static W.Paragraph Para(string text,string? style=null,bool small=false) {
 var prop=new W.ParagraphProperties();if(style!=null)prop.Append(new W.ParagraphStyleId { Val=style });
 var p=new W.Paragraph(prop);var r=new W.Run();if(small)r.RunProperties=new W.RunProperties(new W.Color { Val="595959" },new W.FontSize { Val="18" });
 r.Append(new W.Text(text) { Space=SpaceProcessingModeValues.Preserve });p.Append(r);return p;
}
