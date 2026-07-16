import 'package:web/web.dart' as web;

void openWebmail(String user, String pass) {
  final form = web.HTMLFormElement();
  form.method = 'post';
  form.action = 'https://webmail.sisol.com.mx';
  form.target = '_blank';

  void addField(String name, String value) {
    final input = web.HTMLInputElement();
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    form.append(input);
  }

  addField('_user', user);
  addField('_pass', pass);
  web.document.body!.append(form);
  form.submit();
  form.remove();
}
