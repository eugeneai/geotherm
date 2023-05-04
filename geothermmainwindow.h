#ifndef GEOTHERMMAINWINDOW_H
#define GEOTHERMMAINWINDOW_H

#include <QMainWindow>

QT_BEGIN_NAMESPACE
namespace Ui { class GeothermMainWindow; }
QT_END_NAMESPACE

class GeothermMainWindow : public QMainWindow
{
    Q_OBJECT

public:
    GeothermMainWindow(QWidget *parent = nullptr);
    ~GeothermMainWindow();
public slots:
    void actionAbout ();

private:
    Ui::GeothermMainWindow *ui;
};
#endif // GEOTHERMMAINWINDOW_H
