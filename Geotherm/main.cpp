#include "geothermmainwindow.h"

#include <QApplication>
#include <QLocale>
#include <QTranslator>
#include <QCommandLineParser>
#include "embedding.h"
#include <iostream>

using namespace std;

int main(int argc, char *argv[])
{
  QApplication a(argc, argv);

  QCommandLineParser parser;
  QCommandLineOption noGUIOption("n", "Run without GUI.");
  parser.addOption(noGUIOption);
  parser.process(a);

  bool noGUI = parser.isSet(noGUIOption);
  int retVal = 0;
  cout << "noGui " << noGUI << endl;
  if (noGUI) {
    a.quit();
    start_embedding();
  } else {

    QTranslator translator;
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &locale : uiLanguages) {
      const QString baseName = "Geotherm_" + QLocale(locale).name();
      if (translator.load(":/i18n/" + baseName)) {
        a.installTranslator(&translator);
        break;
      }
    }

    GeothermMainWindow w;
    w.show();
    start_embedding();
    retVal = a.exec();
  }
  exit(end_embedding(retVal));
}
